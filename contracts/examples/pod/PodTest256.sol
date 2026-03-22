// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../mpc/PodLib.sol";
import "../../mpc/PodLibBase.sol";

/// @notice Harness for 256-bit PodLib operations.
contract PodTest256 is PodLib {
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

    function execAdd256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = add256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execSub256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = sub256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMul256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = mul256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execAnd256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = and256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execOr256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = or256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execXor256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = xor256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMin256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = min256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMax256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = max256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execEq256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = eq256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execNe256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = ne256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execGe256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = ge256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execGt256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = gt256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execLe256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = le256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execLt256(itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = lt256(a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execMux256(itBool calldata bit, itUint256 calldata a, itUint256 calldata b) external {
        _reset();
        lastRequestId = mux256(bit, a, b, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execShl256(itUint256 calldata a, uint8 s) external {
        _reset();
        lastRequestId = shl256(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execShr256(itUint256 calldata a, uint8 s) external {
        _reset();
        lastRequestId = shr256(a, s, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execRand256() external {
        _reset();
        lastRequestId = rand256(msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }

    function execRandBoundedBits256(uint8 numBits) external {
        _reset();
        lastRequestId =
            randBoundedBits256(numBits, msg.sender, this.receivePod.selector, PodLibBase.onDefaultMpcError.selector);
    }
}
