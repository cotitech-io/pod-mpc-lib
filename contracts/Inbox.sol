// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./InboxMiner.sol";
import "./MinerBase.sol";

contract Inbox is InboxMiner {
    /// @notice Create an Inbox with the given chain ID.
    /// @param _chainId The chain ID this inbox serves.
    constructor(uint256 _chainId) InboxMiner(_chainId) {}
}
