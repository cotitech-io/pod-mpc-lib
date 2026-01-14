// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IInbox.sol";
import "./IInboxMiner.sol";
import "./InboxMiner.sol";

contract Inbox is InboxMiner {
    constructor(uint256 _chainId) InboxMiner(_chainId) {}
}
