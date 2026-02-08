// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MinerBase is Ownable {
    mapping(address => bool) private _miners;

    event MinerAdded(address miner);
    event MinerRemoved(address miner);

    /// @dev Restrict calls to registered miners.
    modifier onlyMiner() {
        require(_miners[msg.sender], "MinerBase: caller is not a miner");
        _;
    }

    /// @notice Create the miner registry with an initial owner.
    /// @param initialOwner The address to set as owner.
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Adds a miner address
    /// @param miner The miner address to add
    function addMiner(address miner) external onlyOwner {
        require(miner != address(0), "MinerBase: miner is zero address");
        require(!_miners[miner], "MinerBase: already a miner");
        _miners[miner] = true;
        emit MinerAdded(miner);
    }

    /// @notice Removes a miner address
    /// @param miner The miner address to remove
    function removeMiner(address miner) external onlyOwner {
        require(_miners[miner], "MinerBase: not a miner");
        delete _miners[miner];
        emit MinerRemoved(miner);
    }

    /// @notice Checks if an address is a miner
    /// @param miner The address to check
    /// @return True if the address is a miner
    function isMiner(address miner) external view returns (bool) {
        return _miners[miner];
    }
}

