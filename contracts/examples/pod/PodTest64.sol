// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../mpc/PodLib.sol";
import "../../mpc/PodLibBase.sol";

/// @notice Harness: one external call per 64-bit PodLib op; stores raw callback bytes in lastResult.
contract PodTest64 is PodLib {
    bytes public lastResult;
    bytes32 public lastRequestId;

    constructor(address _inbox) {
        setInbox(_inbox);
    }

    function _reset() private {
        lastResult = hex"";
    }

    function receivePod(bytes memory data) external onlyInbox {
        lastResult = data;
    }

    function execAdd64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = add64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execGt64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = gt64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execSub64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = sub64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMul64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = mul64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execDiv64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = div64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execRem64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = rem64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execAnd64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = and64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execOr64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = or64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execXor64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = xor64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMin64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = min64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMax64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = max64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execEq64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = eq64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execNe64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = ne64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execGe64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = ge64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execLe64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = le64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execLt64(itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = lt64(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMux64(itBool calldata bit, itUint64 calldata a, itUint64 calldata b) external {
        _reset();
        lastRequestId = mux64(bit, a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execShl64(itUint64 calldata a, uint8 s) external {
        _reset();
        lastRequestId = shl64(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execShr64(itUint64 calldata a, uint8 s) external {
        _reset();
        lastRequestId = shr64(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execRand64() external {
        _reset();
        lastRequestId = rand64(msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execRandBoundedBits64(uint8 numBits) external {
        _reset();
        lastRequestId =
            randBoundedBits64(numBits, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }
}
