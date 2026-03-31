// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PriceOracle.sol";

/// @title InboxFeeManager
/// @notice Validates cross-chain message fee budgets. Mixed into {InboxBase}.
/// @dev `msg.value` is converted to **gas units** using `tx.gasprice` (or {DEFAULT_GAS_PRICE} if zero). {Request.targetFee} and {Request.callerFee} store gas budgets, not wei. Oracle price ratio maps remote gas budgets when configured; otherwise 1:1.
abstract contract InboxFeeManager {
    /// @notice Template for minimum fees in **gas units** (not wei).
    /// @dev If `constantFee` is non-zero it is the minimum gas units. Else: `(data * gasPerByte + callbackExecutionGas + errorLength * gasPerByte) * bufferRatioX10000 / 10000`.
    struct FeeConfig {
        uint256 constantFee;
        uint256 gasPerByte;
        uint256 callbackExecutionGas;
        uint256 errorLength;
        uint256 bufferRatioX10000;
    }

    /// @notice Oracle used to convert gas budgets between local and remote fee tokens.
    PriceOracle public priceOracle;

    /// @notice Minimum template for the local (callback) leg.
    FeeConfig public localMinFeeConfig;

    /// @notice Minimum template for the remote execution leg.
    FeeConfig public remoteMinFeeConfig;

    /// @notice Fallback gas price (wei) when `tx.gasprice == 0`.
    uint256 public constant DEFAULT_GAS_PRICE = 2_000_000_000 wei;

    /// @dev Reserved execution gas units for error paths (documentation constant; enforcement is application-level).
    uint256 internal constant MIN_GAS_RESERVE_EXECUTION = 100_000;

    error PriceOracleNotInitialized();
    error TotalFeeTooLow(uint256 totalFee);
    error CallbackFeeTooLow(uint256 callbackFee);
    error TargetFeeTooLow(uint256 targetFee);
    error FeeConfigInvalid(FeeConfig feeConfig);
    error CollectFeesZeroAddress();

    /// @notice Send the contract's entire native balance to `to` (typically called by an owner-gated wrapper).
    /// @param to Recipient of accumulated message fees; must not be zero.
    function _collectFees(address payable to) internal {
        if (to == address(0)) revert CollectFeesZeroAddress();
        uint256 amount = address(this).balance;
        if (amount == 0) {
            return;
        }
        (bool ok,) = to.call{value: amount}("");
        require(ok, "Inbox: fee transfer failed");
    }

    function _localRequestExecutionBudget(uint256 totalFee) internal view returns (uint256) {
        if (localMinFeeConfig.constantFee > 0) {
            return totalFee;
        }
        uint256 errorBuffer = localMinFeeConfig.errorLength * localMinFeeConfig.gasPerByte;
        return totalFee > errorBuffer ? totalFee - errorBuffer : 0;
    }

    /// @notice Point the fee manager at a price oracle.
    /// @param priceOracleAddress Oracle contract address.
    function _setPriceOracle(address priceOracleAddress) internal {
        priceOracle = PriceOracle(priceOracleAddress);
    }

    /// @notice Replace minimum fee templates (both must be valid if non-constant).
    /// @param _localMinFeeConfig Local leg template.
    /// @param _remoteMinFeeConfig Remote leg template.
    function _updateMinFeeConfigs(FeeConfig memory _localMinFeeConfig, FeeConfig memory _remoteMinFeeConfig) internal {
        if (
            _localMinFeeConfig.constantFee == 0
                && (
                    _localMinFeeConfig.gasPerByte == 0 || _localMinFeeConfig.callbackExecutionGas == 0
                        || _localMinFeeConfig.errorLength == 0 || _localMinFeeConfig.bufferRatioX10000 == 0
                )
        ) {
            revert FeeConfigInvalid(_localMinFeeConfig);
        }

        if (
            _remoteMinFeeConfig.constantFee == 0
                && (
                    _remoteMinFeeConfig.gasPerByte == 0 || _remoteMinFeeConfig.callbackExecutionGas == 0
                        || _remoteMinFeeConfig.errorLength == 0 || _remoteMinFeeConfig.bufferRatioX10000 == 0
                )
        ) {
            revert FeeConfigInvalid(_remoteMinFeeConfig);
        }
        localMinFeeConfig = _localMinFeeConfig;
        remoteMinFeeConfig = _remoteMinFeeConfig;
    }

    /// @notice Validate two-way payment and compute gas budgets for target and callback legs.
    /// @param dataSize Encoded method call size for template checks.
    /// @param totalFeeLocalWei Total `msg.value` (wei).
    /// @param callbackFeeLocalWei Wei reserved for the callback leg.
    /// @return targetGasRemote Gas units stored as {Request.targetFee} on the remote leg.
    /// @return callerGasLocal Gas units stored as {Request.callerFee} for the callback.
    function validateAndPrepareTwoWayFees(uint256 dataSize, uint256 totalFeeLocalWei, uint256 callbackFeeLocalWei)
        internal
        view
        returns (uint256 targetGasRemote, uint256 callerGasLocal)
    {
        if (totalFeeLocalWei == 0) {
            revert TotalFeeTooLow(totalFeeLocalWei);
        }
        if (callbackFeeLocalWei == 0) {
            revert CallbackFeeTooLow(callbackFeeLocalWei);
        }
        if (callbackFeeLocalWei > totalFeeLocalWei) {
            revert CallbackFeeTooLow(callbackFeeLocalWei);
        }

        uint256 gasPrice = tx.gasprice != 0 ? tx.gasprice : DEFAULT_GAS_PRICE;
        uint256 callbackGasLocal = callbackFeeLocalWei / gasPrice;
        uint256 totalGasLocal = totalFeeLocalWei / gasPrice;
        uint256 remoteGasLocal = totalGasLocal - callbackGasLocal;
        if (callbackGasLocal < expectedMinFee(dataSize, localMinFeeConfig)) {
            revert CallbackFeeTooLow(callbackGasLocal);
        }

        targetGasRemote = validateRemoteFee(dataSize, remoteGasLocal);
        callerGasLocal = callbackGasLocal;
    }

    /// @notice Validate one-way payment and compute remote gas budget.
    /// @param dataSize Encoded method call size for template checks.
    /// @param totalFeeLocalWei Total `msg.value` (wei).
    /// @return targetGasRemote Gas units for {Request.targetFee}; {Request.callerFee} is zero.
    function validateAndPrepareOneWayFees(uint256 dataSize, uint256 totalFeeLocalWei)
        internal
        view
        returns (uint256 targetGasRemote)
    {
        if (totalFeeLocalWei == 0) {
            revert TotalFeeTooLow(totalFeeLocalWei);
        }
        uint256 gasPrice = tx.gasprice != 0 ? tx.gasprice : DEFAULT_GAS_PRICE;
        uint256 totalGasRemote = totalFeeLocalWei / gasPrice;
        targetGasRemote = validateRemoteFee(dataSize, totalGasRemote);
    }

    /// @notice Map remote gas budget using oracle prices (1:1 if oracle missing or prices zero).
    /// @param dataSize Data size for minimum check.
    /// @param remoteGasLocal Gas units before cross-chain adjustment.
    /// @return remoteGasBudget Gas units after adjustment and minimum check.
    function validateRemoteFee(uint256 dataSize, uint256 remoteGasLocal) internal view returns (uint256 remoteGasBudget) {
        if (address(priceOracle) == address(0)) {
            remoteGasBudget = remoteGasLocal;
        } else {
            uint256 localP = priceOracle.getLocalTokenPriceUSDX128();
            uint256 remoteP = priceOracle.getRemoteTokenPriceUSDX128();
            if (localP == 0 || remoteP == 0) {
                remoteGasBudget = remoteGasLocal;
            } else {
                remoteGasBudget = remoteGasLocal * localP / remoteP;
            }
        }
        if (remoteGasBudget < expectedMinFee(dataSize, remoteMinFeeConfig)) {
            revert TargetFeeTooLow(remoteGasBudget);
        }
    }

    /// @notice Minimum gas units from template (no wei conversion).
    /// @param dataSize Payload size for `gasPerByte` terms.
    /// @param feeConfig Template to apply.
    /// @return Gas units required before buffer.
    function expectedMinFee(uint256 dataSize, FeeConfig memory feeConfig) internal pure returns (uint256) {
        if (feeConfig.constantFee > 0) {
            return feeConfig.constantFee;
        }
        uint256 gasUnits = (dataSize * feeConfig.gasPerByte) + feeConfig.callbackExecutionGas
            + (feeConfig.errorLength * feeConfig.gasPerByte);
        return gasUnits * feeConfig.bufferRatioX10000 / 10000;
    }

    /// @notice Off-chain / UI helper: rough native cost at `gasPrice` (return names are historical; not used for on-chain validation).
    /// @param remoteMethodCallSize Remote calldata size term.
    /// @param callBackMethodCallSize Callback calldata size term.
    /// @param remoteMethodExecutionGas Remote execution gas term.
    /// @param callBackMethodExecutionGas Callback execution gas term.
    /// @param gasPrice Wei per gas assumption.
    /// @return targetGasRemote Scaled remote-side estimate.
    /// @return callerGasLocal Scaled callback-side estimate.
    function calculateTwoWayFeeRequired(
        uint256 remoteMethodCallSize,
        uint256 callBackMethodCallSize,
        uint256 remoteMethodExecutionGas,
        uint256 callBackMethodExecutionGas,
        uint256 gasPrice
    ) external view returns (uint256 targetGasRemote, uint256 callerGasLocal) {
        if (remoteMinFeeConfig.constantFee > 0) {
            targetGasRemote = remoteMinFeeConfig.constantFee * gasPrice;
        } else {
            uint256 minRemoteGas = expectedMinFee(remoteMethodCallSize, remoteMinFeeConfig)
                + remoteMethodExecutionGas * gasPrice;
            targetGasRemote = (minRemoteGas + remoteMethodExecutionGas) * gasPrice;
        }
        if (localMinFeeConfig.constantFee > 0) {
            callerGasLocal = localMinFeeConfig.constantFee * gasPrice;
        } else {
            uint256 minLocalGas = expectedMinFee(callBackMethodCallSize, localMinFeeConfig);
            callerGasLocal = (minLocalGas + callBackMethodExecutionGas) * gasPrice;
        }
    }
}
