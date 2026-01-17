// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../mpc/PodMpcLib.sol";
import "../mpc/MpcLib.sol";

contract Adder is MpcUser {
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
            receiveC.selector,
            onDefaultMpcError.selector);
        emit AddRequest(requestId, a, b);
    }

    function receiveC(bytes memory data) external onlyInbox {
        (uint c) = abi.decode(data, (uint));
        result = c;
    }
}
