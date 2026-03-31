// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../mpc/PodLib.sol";
import "../../mpc/PodLibBase.sol";

/// @title PodTest128
/// @notice Test harness for 128-bit {PodLib} operations.
contract PodTest128 is PodLib {
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

    function execAdd128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = add128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execSub128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = sub128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMul128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = mul128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execAnd128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = and128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execOr128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = or128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execXor128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = xor128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMin128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = min128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMax128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = max128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execEq128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = eq128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execNe128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = ne128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execGe128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = ge128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execGt128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = gt128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execLe128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = le128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execLt128(itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = lt128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execMux128(itBool calldata bit, itUint128 calldata a, itUint128 calldata b, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = mux128(bit, a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execShl128(itUint128 calldata a, uint8 s, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = shl128(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execShr128(itUint128 calldata a, uint8 s, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = shr128(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execRand128(uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId = rand128(msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }

    function execRandBoundedBits128(uint8 numBits, uint256 callbackFeeLocalWei) external payable {
        _reset();
        lastRequestId =
            randBoundedBits128(numBits, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector, msg.value, callbackFeeLocalWei);
    }
}
