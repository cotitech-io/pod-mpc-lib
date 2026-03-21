// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../IInbox.sol";
import "./PodUser.sol";
import "../mpccodec/MpcAbiCodec.sol";
import "./coti-side/ICommonMpcMethods.sol";

/**
 * @title PodLib
 * @notice Library-style base for POD MPC: sends two-way messages to the MpcExecutor on COTI.
 *         Extend this contract if you need these MPC helper functions.
 */
abstract contract PodLib is PodUser {
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

    /// @notice Send an MPC add request for 128-bit encrypted inputs to the COTI executor.
    /// @param a Encrypted input a (itUint128).
    /// @param b Encrypted input b (itUint128).
    /// @param cOwner Owner of the result ciphertext.
    /// @param callbackSelector Callback to invoke on success.
    /// @param errorSelector Callback to invoke on error.
    /// @return requestId The created request ID.
    function add128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall =
            MpcAbiCodec.create(ICommonMpcMethods.add128.selector, 3)
            .addArgument(a)
            .addArgument(b)
            .addArgument(cOwner)
            .build();

        return IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            mpcMethodCall,
            callbackSelector,
            errorSelector
        );
    }

    /// @notice Send an MPC add request for 256-bit encrypted inputs to the COTI executor.
    /// @param a Encrypted input a (itUint256).
    /// @param b Encrypted input b (itUint256).
    /// @param cOwner Owner of the result ciphertext.
    /// @param callbackSelector Callback to invoke on success.
    /// @param errorSelector Callback to invoke on error.
    /// @return requestId The created request ID.
    function add256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall =
            MpcAbiCodec.create(ICommonMpcMethods.add256.selector, 3)
            .addArgument(a)
            .addArgument(b)
            .addArgument(cOwner)
            .build();

        return IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            mpcMethodCall,
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
