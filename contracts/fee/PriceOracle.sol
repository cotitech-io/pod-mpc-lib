// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title PriceOracle
/// @notice Base oracle: cached X128 USD-stable prices per wei, optional pull interval, and admin overrides.
/// @dev Subclasses override {fetchLocalTokenPriceUSDX128} / {fetchRemoteTokenPriceUSDX128} to refresh from feeds.
contract PriceOracle is Ownable {
    /// @notice Fixed-point scale `2^128` for prices in {localTokenPriceUSDX128} and {remoteTokenPriceUSDX128}.
    /// @dev Quote per 1 wei of base token, in USD-stable units, scaled by this factor.
    uint256 public constant PRICE_SCALE = 1 << 128;

    /// @notice Minimum seconds between successful pulls in {fetchPrices}. Zero disables the time gate.
    uint256 public fetchInterval;

    /// @notice Block-interval gate for pulls (reserved; use with {fetchInterval} in derived contracts). Zero disables.
    uint256 public fetchBlockInterval;

    /// @notice Timestamp of the last successful pull or admin set.
    uint256 public lastFetchTimestamp;

    /// @notice Cached local execution token price (X128).
    uint256 public localTokenPriceUSDX128;

    /// @notice Cached remote execution token price (X128).
    uint256 public remoteTokenPriceUSDX128;

    /// @notice Address allowed to set prices directly (in addition to {fetchPrices}).
    address public priceAdmin;

    error NotPriceAdmin();

    /// @dev Reverts unless `msg.sender` is {priceAdmin}.
    modifier onlyPriceAdmin() {
        if (msg.sender != priceAdmin) {
            revert NotPriceAdmin();
        }
        _;
    }

    /// @param initialOwner {Ownable} owner; also initial {priceAdmin} so prices can be set without a separate admin tx.
    constructor(address initialOwner) Ownable(initialOwner) {
        priceAdmin = initialOwner;
    }

    /// @notice Refresh cached prices when the time gate allows.
    /// @dev Interval checks are cheap storage reads only. Inbox fee paths use {getLocalTokenPriceUSDX128}/{getRemoteTokenPriceUSDX128} only (no pull). Use {previewFetchPrices} with `estimateGas` when budgeting `fetchPrices`.
    function fetchPrices() external {
        if (!_fetchIntervalsElapsed()) {
            return;
        }

        lastFetchTimestamp = block.timestamp;
        localTokenPriceUSDX128 = fetchLocalTokenPriceUSDX128();
        remoteTokenPriceUSDX128 = fetchRemoteTokenPriceUSDX128();
    }

    /// @notice Minimum seconds between pulls.
    /// @param secondsBetweenFetches New interval (0 = off).
    function setFetchInterval(uint256 secondsBetweenFetches) external onlyOwner {
        fetchInterval = secondsBetweenFetches;
    }

    /// @notice Minimum blocks between pulls (for future use with the time gate).
    /// @param blocksBetweenFetches New interval (0 = off).
    function setFetchBlockInterval(uint256 blocksBetweenFetches) external onlyOwner {
        fetchBlockInterval = blocksBetweenFetches;
    }

    /// @notice Set the address allowed to call {setLocalTokenPriceUSDX128} / {setRemoteTokenPriceUSDX128}.
    /// @param admin Price admin address.
    function setPriceAdmin(address admin) external onlyOwner {
        priceAdmin = admin;
    }

    /// @notice Manually set the local token price (also updates {lastFetchTimestamp}).
    /// @param price X128-scaled price.
    function setLocalTokenPriceUSDX128(uint256 price) external onlyPriceAdmin {
        localTokenPriceUSDX128 = price;
        lastFetchTimestamp = block.timestamp;
    }

    /// @notice Manually set the remote token price (also updates {lastFetchTimestamp}).
    /// @param price X128-scaled price.
    function setRemoteTokenPriceUSDX128(uint256 price) external onlyPriceAdmin {
        remoteTokenPriceUSDX128 = price;
        lastFetchTimestamp = block.timestamp;
    }

    /// @notice Cached local token price (read-only for fee logic).
    /// @return price X128-scaled price.
    function getLocalTokenPriceUSDX128() external view returns (uint256 price) {
        return localTokenPriceUSDX128;
    }

    /// @notice Cached remote token price (read-only for fee logic).
    /// @return price X128-scaled price.
    function getRemoteTokenPriceUSDX128() external view returns (uint256 price) {
        return remoteTokenPriceUSDX128;
    }

    /// @notice Whether {fetchPrices} would update storage at this block.
    /// @return canFetch True if the time gate passes.
    function previewFetchPrices() external view returns (bool canFetch) {
        return _fetchIntervalsElapsed();
    }

    /// @dev True if enough time has passed since {lastFetchTimestamp} for a pull.
    function _fetchIntervalsElapsed() internal view returns (bool) {
        if (fetchInterval != 0 && lastFetchTimestamp != 0 && block.timestamp - lastFetchTimestamp < fetchInterval) {
            return false;
        }
        return true;
    }

    /// @dev Override to pull local token price; default returns the cache.
    function fetchLocalTokenPriceUSDX128() internal view virtual returns (uint256) {
        return localTokenPriceUSDX128;
    }

    /// @dev Override to pull remote token price; default returns the cache.
    function fetchRemoteTokenPriceUSDX128() internal view virtual returns (uint256) {
        return remoteTokenPriceUSDX128;
    }
}
