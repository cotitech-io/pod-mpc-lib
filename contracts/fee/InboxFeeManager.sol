// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./PriceOracle.sol";

/**
 * @title InboxFeeManager
 * @notice Validates minimum fee budgets for cross-chain inbox messages. Mixed into {InboxBase}.
 * @dev **Gas units vs native token**
 *      Callers pay the **native execution token** (e.g. ETH) via `msg.value` at the **current** `tx.gasprice`.
 *      The fee manager converts that payment to **gas units** by dividing wei by `gasPrice` (using
 *      {DEFAULT_GAS_PRICE} when `tx.gasprice` is zero). All values **stored on `Request.targetFee` and
 *      `Request.callerFee`** are **gas unit budgets** for the corresponding execution leg on the **target**
 *      or **callback** chain. Execution code (e.g. {InboxMiner}) must **not** multiply or divide those
 *      fields by `gasPrice`—they are already gas limits / budgets.
 *      When the price oracle has no prices (0), remote leg conversion uses 1:1 gas-unit equivalence for development.
 */
abstract contract InboxFeeManager {
    error PriceOracleNotInitialized();
    error TotalFeeTooLow(uint256 totalFee);
    error CallbackFeeTooLow(uint256 callbackFee);
    error TargetFeeTooLow(uint256 targetFee);
    error FeeConfigInvalid(FeeConfig feeConfig);

    /**
     * @notice Minimum fee templates, expressed in **gas units** (not wei).
     * @dev If `constantFee` is set, it is the minimum **gas units** required.
     *      Otherwise: `[(data_size * gasPerByte) + callbackExecutionGas + (errorLength * gasPerByte)] * bufferRatio / 10000`
     *      (pure gas-unit arithmetic; no `gasPrice` here).
     */
    struct FeeConfig {
        uint256 constantFee;
        uint256 gasPerByte;
        uint256 callbackExecutionGas;
        uint256 errorLength;
        uint256 bufferRatioX10000;
    }

    PriceOracle public priceOracle;
    FeeConfig public localMinFeeConfig;
    FeeConfig public remoteMinFeeConfig;

    uint256 public constant DEFAULT_GAS_PRICE = 2_000_000_000 wei;

    /// @dev Reserve gas units so a failed target call can still record {errors} / emit {ErrorReceived}.
    uint256 internal constant MIN_GAS_RESERVE_EXECUTION = 100_000;

    function _setPriceOracle(address priceOracleAddress) internal {
        priceOracle = PriceOracle(priceOracleAddress);
    }

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

    /// @notice Two-way: `totalFeeLocalWei` is `msg.value`; `callbackFeeLocalWei` is the wei slice for the return-leg (local chain) at this tx's gas price.
    /// @return targetGasRemote Gas unit budget stored on the outgoing request for **remote** execution (`Request.targetFee`).
    /// @return callerGasLocal Gas unit budget stored for the **callback** leg on the source chain (`Request.callerFee`).
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
        // Convert payment from wei to gas units at this transaction's gas price.
        uint256 callbackGasLocal = callbackFeeLocalWei / gasPrice;
        uint256 totalGasLocal = totalFeeLocalWei / gasPrice;
        uint256 remoteGasLocal = totalGasLocal - callbackGasLocal;
        if (callbackGasLocal < expectedMinFee(dataSize, localMinFeeConfig)) {
            revert CallbackFeeTooLow(callbackGasLocal);
        }

        targetGasRemote = validateRemoteFee(dataSize, remoteGasLocal);
        callerGasLocal = callbackGasLocal;
    }

    /// @notice One-way: converts `msg.value` to gas units then validates the remote leg minimum.
    /// @return targetGasRemote Gas unit budget for **remote** execution (`Request.targetFee`). `Request.callerFee` is zero.
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

    /// @dev Maps the **remote-execution gas budget** (gas units on the local fee token basis) to gas units on the remote chain using the oracle; 1:1 if oracle unset or prices zero.
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

    function calculateTwoWayFeeRequired(uint256 remoteMethodCallSize, uint256 callBackMethodCallSize,
    uint256 remoteMethodExecutionGas, uint256 callBackMethodExecutionGas, uint256 gasPrice
    ) external view returns (uint256 targetGasRemote, uint256 callerGasLocal) {
        // The actual fee required to pay is:
        // remote_copy_gas + remote_exec_gas + buffer +
        // callback_copy_gas + callback_exec_gas + buffer
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

    /// @return Minimum required gas units from template (no wei / gasPrice).
    function expectedMinFee(uint256 dataSize, FeeConfig memory feeConfig) internal pure returns (uint256) {
        if (feeConfig.constantFee > 0) {
            return feeConfig.constantFee;
        }
        uint256 gasUnits = (dataSize * feeConfig.gasPerByte) + feeConfig.callbackExecutionGas
            + (feeConfig.errorLength * feeConfig.gasPerByte);
        return gasUnits * feeConfig.bufferRatioX10000 / 10000;
    }
}
