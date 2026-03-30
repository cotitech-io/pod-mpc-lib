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
        if (!_fetchIntervalsElapsed()) {
            return;
        }

        lastFetchTimestamp = block.timestamp;
        localTokenPriceUSDX128 = fetchLocalTokenPriceUSDX128();
        remoteTokenPriceUSDX128 = fetchRemoteTokenPriceUSDX128();
    }

    function _fetchIntervalsElapsed() internal view returns (bool) {
        if (fetchInterval != 0 && lastFetchTimestamp != 0 && block.timestamp - lastFetchTimestamp < fetchInterval) {
            return false;
        }
        return true;
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
    }

    function setRemoteTokenPriceUSDX128(uint256 price) external onlyPriceAdmin {
        remoteTokenPriceUSDX128 = price;
        lastFetchTimestamp = block.timestamp;
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