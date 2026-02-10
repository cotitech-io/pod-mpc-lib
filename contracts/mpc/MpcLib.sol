// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../IInbox.sol";
import "./MpcUser.sol";
import "../mpccodec/MpcAbiCodec.sol";
import "./coti-side/ICommonMpcMethods.sol";

/**
 * @title MpcLib
 * @notice This is the library contract for the MPC methods. It is used to send two-way messages
 *         to the MpcExecutor contract on the COTI side.
 *         Extend this contrct if you need these Mpc library functions.
 */
abstract contract MpcLib is MpcUser {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    /// @notice Send an MPC add request to the COTI executor.
    /// @param a Encrypted input a (itUint64).
    /// @param b Encrypted input b (itUint64).
    /// @param cOwner Owner of the result ciphertext.
    /// @param callbackSelector Callback to invoke on success.
    /// @param errorSelector Callback to invoke on error.
    /// @return requestId The created request ID.
    function add(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        IInbox.MpcMethodCall memory methodCall =
            MpcAbiCodec.create(ICommonMpcMethods.add.selector, 3)
            .addArgument(a) // For gt data type, we use it equivalent, which is user encrypted
            .addArgument(b)
            .addArgument(cOwner)
            .build();

        return IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            callbackSelector,
            errorSelector
        );
    }

    function gt(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        IInbox.MpcMethodCall memory methodCall =
            MpcAbiCodec.create(ICommonMpcMethods.gt.selector, 3)
            .addArgument(a) // For gt data type, we use it equivalent, which is user encrypted
            .addArgument(b)
            .addArgument(cOwner)
            .build();

        return IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            callbackSelector,
            errorSelector
        );
    }


    /// @notice Default error handler for MPC requests.
    /// @param requestId The failed request ID.
    function onDefaultMpcError(bytes32 requestId) external onlyInbox {
        (uint code, string memory message) = inbox.getOutboxError(requestId);
        emit ErrorRemoteCall(requestId, code, message);
    }
}



