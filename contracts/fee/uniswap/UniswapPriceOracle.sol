// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "../PriceOracle.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Minimal Uniswap V2 pair surface for spot pricing from reserves.
interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

/**
 * @title UniswapPriceOracle
 * @notice Caches Uniswap V2 spot ratios as **quote per 1 wei of base**, scaled by `2^128` (same as {PriceOracle.PRICE_SCALE}).
 * @dev **Caching & refresh**
 *      - **Reads used by inbox fee math** (`getLocalTokenPriceUSDX128` / `getRemoteTokenPriceUSDX128`) only return **cached**
 *        storage. They **never** call `getReserves`, so `estimateGas` on `sendMessage` paths matches execution gas for
 *        oracle reads (no surprise Uniswap pull when the tx is mined).
 *      - **Uniswap** is queried **only** inside {PriceOracle.fetchPrices} (via internal `fetch*TokenPriceUSDX128` overrides),
 *        **after** interval gates in the parent. **Cheap revert** (`FetchIntervalNotMet`) does **not** touch the pair.
 * @dev **`estimateGas` vs `fetchPrices`**
 *      - A `fetchPrices` tx can still spend **more** gas on a later mined block if both interval gates pass (pulls) vs
 *        simulation (revert) — that is revert vs success, not silent OOG on an unrelated inbox tx.
 *      - To align gas for **only** `fetchPrices`, call {PriceOracle.previewFetchPrices} at the same block tag as
 *        `estimateGas`; if `canFetch` is true, budget for the full pull path.
 * @dev Spot reserves are **manipulable**; production should prefer TWAP or a trusted feed.
 */
contract UniswapPriceOracle is PriceOracle {
    error UniswapPriceOracleZeroReserves();

    IUniswapV2Pair public immutable localPair;
    IUniswapV2Pair public immutable remotePair;

    /// @dev If true, the “local” chain native (or its wrapped ERC20) is token0 in `localPair`; else it is token1.
    bool public immutable localTokenIsToken0;
    /// @dev If true, the “remote” chain native (or its wrapped ERC20) is token0 in `remotePair`; else it is token1.
    bool public immutable remoteTokenIsToken0;

    /**
     * @param initialOwner Passed to {PriceOracle}.
     * @param _localPair V2 pair on **this** chain for the **local** execution token vs a USD-stable quote asset.
     * @param _remotePair V2 pair on **this** chain for the **remote** execution token vs the **same** quote asset.
     * @param _localTokenIsToken0 Whether the local native (wrapped) is `token0` in `_localPair`.
     * @param _remoteTokenIsToken0 Whether the remote native (wrapped) is `token0` in `_remotePair`.
     * @param _fetchIntervalSeconds Minimum seconds between pulls (0 = no time gate).
     * @param _fetchIntervalBlocks Minimum blocks between pulls (0 = no block gate). Using both gates can reduce
     *        boundary crossing between simulation and mining for `fetchPrices`-only transactions.
     */
    constructor(
        address initialOwner,
        IUniswapV2Pair _localPair,
        IUniswapV2Pair _remotePair,
        bool _localTokenIsToken0,
        bool _remoteTokenIsToken0,
        uint256 _fetchIntervalSeconds,
        uint256 _fetchIntervalBlocks
    ) PriceOracle(initialOwner) {
        localPair = _localPair;
        remotePair = _remotePair;
        localTokenIsToken0 = _localTokenIsToken0;
        remoteTokenIsToken0 = _remoteTokenIsToken0;
        fetchInterval = _fetchIntervalSeconds;
        fetchBlockInterval = _fetchIntervalBlocks;
    }

    /// @dev Quote per 1 wei of “local” token, X128-fixed.
    function fetchLocalTokenPriceUSDX128() internal view override returns (uint256) {
        return _spotPriceX128(localPair, localTokenIsToken0);
    }

    /// @dev Quote per 1 wei of “remote” token, X128-fixed.
    function fetchRemoteTokenPriceUSDX128() internal view override returns (uint256) {
        return _spotPriceX128(remotePair, remoteTokenIsToken0);
    }

    /**
     * @dev Spot “quote per base” with X128 scaling: `(quoteReserve * 2^128) / baseReserve`.
     *      When `baseIsToken0`, base = reserve0, quote = reserve1; otherwise base = reserve1, quote = reserve0.
     */
    function _spotPriceX128(IUniswapV2Pair pair, bool baseIsToken0) private view returns (uint256) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 base;
        uint256 quote;
        if (baseIsToken0) {
            base = uint256(r0);
            quote = uint256(r1);
        } else {
            base = uint256(r1);
            quote = uint256(r0);
        }
        if (base == 0) {
            revert UniswapPriceOracleZeroReserves();
        }
        return Math.mulDiv(quote, PRICE_SCALE, base);
    }
}
