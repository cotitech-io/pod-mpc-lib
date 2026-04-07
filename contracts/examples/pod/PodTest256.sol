// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../mpc/PodLib.sol";
import "../../mpc/PodLibBase.sol";

/// @title PodTest256
/// @notice Test harness for 256-bit {PodLib} operations.
contract PodTest256 is PodLib {
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

    function execAdd256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = add256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execSub256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = sub256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMul256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = mul256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execAnd256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = and256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execOr256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = or256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execXor256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = xor256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMin256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = min256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMax256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = max256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execEq256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = eq256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execNe256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = ne256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execGe256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = ge256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execGt256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = gt256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execLe256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = le256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execLt256(itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = lt256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMux256(itBool calldata bit, itUint256 calldata a, itUint256 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = mux256(bit, a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execShl256(itUint256 calldata a, uint8 s, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = shl256(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execShr256(itUint256 calldata a, uint8 s, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = shr256(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execRand256(uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = rand256(msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execRandBoundedBits256(uint8 numBits, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId =
            randBoundedBits256(numBits, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }
}
