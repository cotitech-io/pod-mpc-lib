// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../mpc/PodLib.sol";
import "../../mpc/PodLibBase.sol";

/// @notice Harness for 128-bit PodLib operations.
contract PodTest128 is PodLib {
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

    function execAdd128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = add128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execSub128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = sub128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMul128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = mul128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execAnd128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = and128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execOr128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = or128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execXor128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = xor128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMin128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = min128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMax128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = max128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execEq128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = eq128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execNe128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = ne128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execGe128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = ge128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execGt128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = gt128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execLe128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = le128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execLt128(itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = lt128(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMux128(itBool calldata bit, itUint128 calldata a, itUint128 calldata b) external {
        _reset();
        lastRequestId = mux128(bit, a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execShl128(itUint128 calldata a, uint8 s) external {
        _reset();
        lastRequestId = shl128(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execShr128(itUint128 calldata a, uint8 s) external {
        _reset();
        lastRequestId = shr128(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execRand128() external {
        _reset();
        lastRequestId = rand128(msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execRandBoundedBits128(uint8 numBits) external {
        _reset();
        lastRequestId =
            randBoundedBits128(numBits, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }
}
