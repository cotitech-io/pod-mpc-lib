// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../IInbox.sol";
import "../InboxUser.sol";

abstract contract MpcUser is InboxUser {
    event ErrorRemoteCall(bytes32 requestId, uint code, string message);

    address internal mpcExecutorAddress = 0x0000000000000000000000000000000000000000;
    uint256 internal cotiChainId = 2632500;

    function configureCoti(address _mpcExecutorAddress, uint256 _cotiChainId) public virtual {
        mpcExecutorAddress = _mpcExecutorAddress;
        cotiChainId = _cotiChainId;
    }
}