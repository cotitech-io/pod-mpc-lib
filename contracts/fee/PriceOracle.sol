// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.19;

contract PriceOracle is Ownable {
    error FetchIntervalNotMet();
    // 128 bits for the price, 128 bits for the timestamp   
    uint256 constant public PRICE_SCALE = 1 << 128;
    uint256 public fetchInterval;
    uint256 public lastFetchTimestamp;
    uint256 public localTokenPriceUSDX128; // eth
    uint256 public remoteTokenPriceUSDX128; // coti

    constructor(address initialOwner) Ownable(initialOwner) {}

    function fetchPrices() external {
        if (block.timestamp - lastFetchTimestamp < fetchInterval) {
            revert FetchIntervalNotMet();
        }
        lastFetchTimestamp = block.timestamp;
        localTokenPriceUSDX128 = fetchLocalTokenPriceUSDX128();
        remoteTokenPriceUSDX128 = fetchRemoteTokenPriceUSDX128();
    }

    function getLocalTokenPriceUSDX128() external view returns (uint256) {
        return localTokenPriceUSDX128;
    }
    
    function getRemoteTokenPriceUSDX128() external view returns (uint256) {
        return remoteTokenPriceUSDX128;
    }

    function fetchLocalTokenPriceUSDX128() internal view returns (uint256) {
        // TODO: Fetch price from uniswap pool
        return 0;
    }

    function fetchRemoteTokenPriceUSDX128() internal view returns (uint256) {
        // TODO:Fetch price from uniswap pool
        return 0;
    }
}