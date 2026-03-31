// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../mpc/PodLib.sol";
import "../../mpc/PodLibBase.sol";

/// @title PodTest64
/// @notice Test harness: one external per 64-bit {PodLib} op; stores last callback bytes.
contract PodTest64 is PodLib {
    bytes public lastResult;
    bytes32 public lastRequestId;

    constructor(address _inbox) PodLibBase(msg.sender) {
        setInbox(_inbox);
    }

    function _reset() private {
        lastResult = hex"";
    }

    function receivePod(bytes memory data) external onlyInbox {
        lastResult = data;
    }

    function execAdd64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = add64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execGt64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = gt64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execSub64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = sub64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMul64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = mul64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execDiv64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = div64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execRem64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = rem64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execAnd64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = and64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execOr64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = or64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execXor64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = xor64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMin64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = min64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMax64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = max64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execEq64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = eq64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execNe64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = ne64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execGe64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = ge64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execLe64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = le64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execLt64(itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = lt64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMux64(itBool calldata bit, itUint64 calldata a, itUint64 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = mux64(bit, a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execShl64(itUint64 calldata a, uint8 s, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = shl64(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execShr64(itUint64 calldata a, uint8 s, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = shr64(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execRand64(uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = rand64(msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execRandBoundedBits64(uint8 numBits, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId =
            randBoundedBits64(numBits, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }
}
