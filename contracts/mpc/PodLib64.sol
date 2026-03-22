// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../IInbox.sol";
import "../mpccodec/MpcAbiCodec.sol";
import "./PodLibBase.sol";
import "./coti-side/IPodExecutorOps.sol";

/**
 * @title PodLib64
 * @notice 64-bit POD MPC calls (itUint64 / ctUint64) and comparison to ctBool.
 */
abstract contract PodLib64 is PodLibBase {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    function add64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.add64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function gt64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.gt64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function sub64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.sub64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function mul64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.mul64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function div64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.div64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function rem64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.rem64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function and64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.and64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function or64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.or64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function xor64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.xor64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function min64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.min64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function max64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.max64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function eq64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.eq64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function ne64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.ne64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function ge64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.ge64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function le64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.le64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function lt64(
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree(IPodExecutor64.lt64.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function mux64(
        itBool memory bit,
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall = MpcAbiCodec.create(IPodExecutor64.mux64.selector, 4)
            .addArgument(bit)
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

    function shl64(
        itUint64 memory a,
        uint8 s,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendShift(IPodExecutor64.shl64.selector, a, s, cOwner, callbackSelector, errorSelector);
    }

    function shr64(
        itUint64 memory a,
        uint8 s,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendShift(IPodExecutor64.shr64.selector, a, s, cOwner, callbackSelector, errorSelector);
    }

    /// @dev Callback `data` is `abi.encode(uint256)` plaintext (executor decrypts MPC rand on COTI).
    function rand64(address cOwner, bytes4 callbackSelector, bytes4 errorSelector) internal returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall =
            MpcAbiCodec.create(IPodExecutor64.rand64.selector, 1).addArgument(cOwner).build();

        return IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            mpcMethodCall,
            callbackSelector,
            errorSelector
        );
    }

    /// @dev Callback `data` is `abi.encode(uint256)` plaintext.
    function randBoundedBits64(
        uint8 numBits,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall = MpcAbiCodec.create(IPodExecutor64.randBoundedBits64.selector, 2)
            .addArgument(uint256(uint8(numBits)))
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

    function _sendThree(
        bytes4 selector,
        itUint64 memory a,
        itUint64 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) private returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall =
            MpcAbiCodec.create(selector, 3).addArgument(a).addArgument(b).addArgument(cOwner).build();

        return IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            mpcMethodCall,
            callbackSelector,
            errorSelector
        );
    }

    function _sendShift(
        bytes4 selector,
        itUint64 memory a,
        uint8 s,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) private returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall = MpcAbiCodec.create(selector, 3)
            .addArgument(a)
            .addArgument(uint256(uint8(s)))
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
}
