// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./InboxMiner.sol";
import "./MinerBase.sol";

contract Inbox is InboxMiner, MinerBase {
    constructor(uint256 _chainId) InboxMiner(_chainId) MinerBase(msg.sender) {}
}
