// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../mpc/MpcLib.sol";

contract Adder is MpcLib {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;
    event AddRequest(bytes32 requestId, uint a, uint b);

    uint public result;

    /// @notice Create an example adder bound to an inbox.
    /// @param _inbox The inbox contract address.
    constructor(address _inbox) {
        setInbox(_inbox);
    }

    /// @notice Send a two-way add request to the MPC executor.
    /// @param a First operand (plaintext).
    /// @param b Second operand (plaintext).
    /// @param cOwner Owner of the result ciphertext.
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

    /// @notice Receive the response and store the decoded result.
    /// @param data The response payload containing the result.
    function receiveC(bytes memory data) external onlyInbox {
        (uint c) = abi.decode(data, (uint));
        result = c;
    }
}
