// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../PriceOracle.sol";

/// @notice Minimal Uniswap V2 pair surface for reserve-based spot pricing.
interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

/// @title UniswapPriceOracle
/// @notice {PriceOracle} implementation that reads Uniswap V2 reserves for local and remote token USD quotes.
/// @dev Cached reads for fee math; Uniswap is touched only inside {PriceOracle.fetchPrices} after interval checks. Spot reserves are manipulable—prefer TWAP or trusted feeds in production.
contract UniswapPriceOracle is PriceOracle {
    error UniswapPriceOracleZeroReserves();

    IUniswapV2Pair public immutable localPair;
    IUniswapV2Pair public immutable remotePair;

    /// @dev If true, the local base token is `token0` in {localPair}.
    bool public immutable localTokenIsToken0;

    /// @dev If true, the remote base token is `token0` in {remotePair}.
    bool public immutable remoteTokenIsToken0;

    /// @param initialOwner Passed to {PriceOracle}.
    /// @param _localPair V2 pair for local execution token vs USD-stable quote on this chain.
    /// @param _remotePair V2 pair for remote execution token vs the same quote on this chain.
    /// @param _localTokenIsToken0 Whether the local base is `token0` in `_localPair`.
    /// @param _remoteTokenIsToken0 Whether the remote base is `token0` in `_remotePair`.
    /// @param _fetchIntervalSeconds Minimum seconds between pulls (0 = no time gate).
    /// @param _fetchIntervalBlocks Minimum blocks between pulls (0 = no block gate).
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

    /// @dev Overrides parent to read spot price from {localPair}.
    function fetchLocalTokenPriceUSDX128() internal view override returns (uint256) {
        return _spotPriceX128(localPair, localTokenIsToken0);
    }

    /// @dev Overrides parent to read spot price from {remotePair}.
    function fetchRemoteTokenPriceUSDX128() internal view override returns (uint256) {
        return _spotPriceX128(remotePair, remoteTokenIsToken0);
    }

    /// @dev Spot quote per base wei: `(quoteReserve * PRICE_SCALE) / baseReserve`.
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
