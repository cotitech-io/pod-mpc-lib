// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../IInbox.sol";
import "../mpccodec/MpcAbiCodec.sol";
import "./PodLibBase.sol";
import "./coti-side/IPodExecutorOps.sol";

/**
 * @title PodLib256
 * @notice 256-bit POD MPC (itUint256 / ctUint256).
 */
abstract contract PodLib256 is PodLibBase {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    function add256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.add256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function sub256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.sub256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function mul256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.mul256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function and256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.and256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function or256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.or256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function xor256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.xor256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function min256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.min256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function max256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.max256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function eq256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.eq256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function ne256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.ne256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function ge256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.ge256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function gt256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.gt256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function le256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.le256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function lt256(
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree256(IPodExecutor256.lt256.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function mux256(
        itBool memory bit,
        itUint256 memory a,
        itUint256 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall = MpcAbiCodec.create(IPodExecutor256.mux256.selector, 4)
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

    function shl256(
        itUint256 memory a,
        uint8 s,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendShift256(IPodExecutor256.shl256.selector, a, s, cOwner, callbackSelector, errorSelector);
    }

    function shr256(
        itUint256 memory a,
        uint8 s,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendShift256(IPodExecutor256.shr256.selector, a, s, cOwner, callbackSelector, errorSelector);
    }

    /// @dev Callback `data` is `abi.encode(uint256)` plaintext (executor decrypts MPC rand on COTI).
    function rand256(address cOwner, bytes4 callbackSelector, bytes4 errorSelector) internal returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall =
            MpcAbiCodec.create(IPodExecutor256.rand256.selector, 1).addArgument(cOwner).build();

        return IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            mpcMethodCall,
            callbackSelector,
            errorSelector
        );
    }

    /// @dev Callback `data` is `abi.encode(uint256)` plaintext.
    function randBoundedBits256(
        uint8 numBits,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall = MpcAbiCodec.create(IPodExecutor256.randBoundedBits256.selector, 2)
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

    function _sendThree256(
        bytes4 selector,
        itUint256 memory a,
        itUint256 memory b,
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

    function _sendShift256(
        bytes4 selector,
        itUint256 memory a,
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
