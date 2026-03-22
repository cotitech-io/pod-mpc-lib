// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../IInbox.sol";
import "../mpccodec/MpcAbiCodec.sol";
import "./PodLibBase.sol";
import "./coti-side/IPodExecutorOps.sol";

/**
 * @title PodLib128
 * @notice 128-bit POD MPC (itUint128 / ctUint128).
 */
abstract contract PodLib128 is PodLibBase {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    function add128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.add128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function sub128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.sub128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function mul128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.mul128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function and128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.and128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function or128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.or128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function xor128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.xor128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function min128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.min128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function max128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.max128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function eq128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.eq128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function ne128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.ne128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function ge128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.ge128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function gt128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.gt128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function le128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.le128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function lt128(
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendThree128(IPodExecutor128.lt128.selector, a, b, cOwner, callbackSelector, errorSelector);
    }

    function mux128(
        itBool memory bit,
        itUint128 memory a,
        itUint128 memory b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall = MpcAbiCodec.create(IPodExecutor128.mux128.selector, 4)
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

    function shl128(
        itUint128 memory a,
        uint8 s,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendShift128(IPodExecutor128.shl128.selector, a, s, cOwner, callbackSelector, errorSelector);
    }

    function shr128(
        itUint128 memory a,
        uint8 s,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _sendShift128(IPodExecutor128.shr128.selector, a, s, cOwner, callbackSelector, errorSelector);
    }

    /// @dev Callback `data` is `abi.encode(uint256)` plaintext (executor decrypts MPC rand on COTI).
    function rand128(address cOwner, bytes4 callbackSelector, bytes4 errorSelector) internal returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall =
            MpcAbiCodec.create(IPodExecutor128.rand128.selector, 1).addArgument(cOwner).build();

        return IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            mpcMethodCall,
            callbackSelector,
            errorSelector
        );
    }

    /// @dev Callback `data` is `abi.encode(uint256)` plaintext.
    function randBoundedBits128(
        uint8 numBits,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        IInbox.MpcMethodCall memory mpcMethodCall = MpcAbiCodec.create(IPodExecutor128.randBoundedBits128.selector, 2)
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

    function _sendThree128(
        bytes4 selector,
        itUint128 memory a,
        itUint128 memory b,
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

    function _sendShift128(
        bytes4 selector,
        itUint128 memory a,
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
