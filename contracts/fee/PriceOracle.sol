// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.19;

contract PriceOracle is Ownable {
    error FetchIntervalNotMet();
    error NotPriceAdmin();
    /// @notice Fixed-point scale `2^128` for USD-quoted prices stored in {localTokenPriceUSDX128} and {remoteTokenPriceUSDX128}.
    /// @dev Values are “quote token (in USD-stable units) per 1 wei of base”, multiplied by this scale so they fit in uint256 math.
    uint256 public constant PRICE_SCALE = 1 << 128;
    /// @notice Minimum seconds between on-chain price pulls via {fetchPrices}. Set to 0 to disable the time gate.
    uint256 public fetchInterval;
    /// @notice Minimum block distance between pulls when non-zero; 0 disables the block gate.
    /// @dev Combined with {fetchInterval}: both gates must pass (when enabled) before Uniswap is queried.
    uint256 public fetchBlockInterval;
    uint256 public lastFetchTimestamp;
    uint256 public lastFetchBlock;
    uint256 public localTokenPriceUSDX128; // eth
    uint256 public remoteTokenPriceUSDX128; // coti
    address public priceAdmin;

    modifier onlyPriceAdmin() {
        if (msg.sender != priceAdmin) {
            revert NotPriceAdmin();
        }
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Updates cached prices by calling {fetchLocalTokenPriceUSDX128} / {fetchRemoteTokenPriceUSDX128}.
    /// @dev **Gas / `estimateGas` safety**
    ///      - Interval checks use only storage reads and **run before** any virtual fetch (no Uniswap on revert path).
    ///      - **Fee validation** in {InboxFeeManager} only calls {getLocalTokenPriceUSDX128} / {getRemoteTokenPriceUSDX128},
    ///        which read **cached** values and never pull oracles — so send-message gas does not depend on refresh timing.
    ///      - For this function only: use {previewFetchPrices} at the same `block.tag` as `estimateGas` to see whether
    ///        the expensive branch will run; if `canFetch` differs between simulation and mining, your `fetchPrices` tx
    ///        can still revert or use different gas — prefer a generous gas limit or a separate `fetchPrices` tx.
    function fetchPrices() external {
        _requireFetchIntervalsElapsed();
        lastFetchTimestamp = block.timestamp;
        lastFetchBlock = block.number;
        localTokenPriceUSDX128 = fetchLocalTokenPriceUSDX128();
        remoteTokenPriceUSDX128 = fetchRemoteTokenPriceUSDX128();
    }

    /// @notice Same interval logic as {fetchPrices} but view-only: returns whether a {fetchPrices} call would pull new
    ///         prices and the prices that would be written (without storing). Use off-chain or in `eth_call` to align
    ///         gas estimates with the branch you expect at a given block.
    function previewFetchPrices()
        external
        view
        returns (bool canFetch, uint256 localPrice, uint256 remotePrice)
    {
        if (!_fetchIntervalsElapsed()) {
            return (false, localTokenPriceUSDX128, remoteTokenPriceUSDX128);
        }
        return (true, fetchLocalTokenPriceUSDX128(), fetchRemoteTokenPriceUSDX128());
    }

    function _fetchIntervalsElapsed() internal view returns (bool) {
        if (fetchInterval != 0 && lastFetchTimestamp != 0 && block.timestamp - lastFetchTimestamp < fetchInterval) {
            return false;
        }
        if (fetchBlockInterval != 0 && lastFetchBlock != 0 && block.number < lastFetchBlock + fetchBlockInterval) {
            return false;
        }
        return true;
    }

    function _requireFetchIntervalsElapsed() internal view {
        if (!_fetchIntervalsElapsed()) {
            revert FetchIntervalNotMet();
        }
    }

    function setFetchInterval(uint256 secondsBetweenFetches) external onlyOwner {
        fetchInterval = secondsBetweenFetches;
    }

    function setFetchBlockInterval(uint256 blocksBetweenFetches) external onlyOwner {
        fetchBlockInterval = blocksBetweenFetches;
    }

    function setPriceAdmin(address admin) external onlyOwner {
        priceAdmin = admin;
    }

    function setLocalTokenPriceUSDX128(uint256 price) external onlyPriceAdmin {
        localTokenPriceUSDX128 = price;
        lastFetchTimestamp = block.timestamp;
        lastFetchBlock = block.number;
    }

    function setRemoteTokenPriceUSDX128(uint256 price) external onlyPriceAdmin {
        remoteTokenPriceUSDX128 = price;
        lastFetchTimestamp = block.timestamp;
        lastFetchBlock = block.number;
    }

    function getLocalTokenPriceUSDX128() external view returns (uint256) {
        return localTokenPriceUSDX128;
    }
    
    function getRemoteTokenPriceUSDX128() external view returns (uint256) {
        return remoteTokenPriceUSDX128;
    }

    function fetchLocalTokenPriceUSDX128() internal virtual view returns (uint256) {
        return localTokenPriceUSDX128;
    }

    function fetchRemoteTokenPriceUSDX128() internal virtual view returns (uint256) {
        return remoteTokenPriceUSDX128;
    }
}