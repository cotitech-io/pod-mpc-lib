// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../InboxUser.sol";
import "../mpc/PodMpcLib.sol";

contract Adder is InboxUser {
    event ErrorRemoteCall(bytes32 requestId, uint code, string message);
    event AddRequest(bytes32 requestId, uint a, uint b);

    // TODO: Use the mpc 
    uint public result;

    constructor(address _inbox) {
        setInbox(_inbox);
    }

    function add(uint a, uint b) external {
        bytes32 requestId = PodMpcLib.add(
            inbox,
            a, b,
            msg.sender, // Who can decrypt the result
            Adder.receiveC.selector,
            Adder.onError.selector);
        emit AddRequest(requestId, a, b);
    }

    function onError(bytes32 requestId) external onlyInbox {
        (uint code, string memory message) = inbox.getOutboxError(requestId);
        emit ErrorRemoteCall(requestId, code, message);
    }

    function receiveC(bytes memory data) external onlyInbox {
        (uint c) = abi.decode(data, (uint));
        result = c;
    }
}
