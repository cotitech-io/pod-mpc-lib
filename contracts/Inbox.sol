// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./InboxMiner.sol";
import "./MinerBase.sol";

/// @title Inbox
/// @notice Production inbox: combines {InboxMiner} routing with {MinerBase} access control.
contract Inbox is InboxMiner {
    /// @param _chainId This chain's ID (0 means use `block.chainid` in {InboxBase}).
    constructor(uint256 _chainId) InboxMiner(_chainId) {}
}
