// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../mpc/MpcLib.sol";

contract Adder is MpcLib {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;
    event AddRequest(bytes32 requestId, uint a, uint b);

    uint public result;

    constructor(address _inbox) {
        setInbox(_inbox);
    }

    function add(uint a, uint b, address cOwner) external {
        // Need to create a custom request as the MpcLib only implements mpc calls
        IInbox.MpcMethodCall memory methodCall =
            MpcAbiCodec.create(ICommonMpcMethods.add.selector, 3)
            .addArgument(a) // For gt data type, we use it equivalent, which is user encrypted
            .addArgument(b)
            .addArgument(cOwner)
            .build();
        bytes32 requestId = IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            Adder.receiveC.selector,
            MpcLib.onDefaultMpcError.selector
        );
        emit AddRequest(requestId, a, b);
    }

    function receiveC(bytes memory data) external onlyInbox {
        (uint c) = abi.decode(data, (uint));
        result = c;
    }
}
