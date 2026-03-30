// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../InboxUser.sol";
import "./IPodExecutorOps.sol";

/// @title MpcExecutor
/// @notice COTI-side MPC executor: routes `onlyInbox` calls to `MpcCore` for 64/128/256-bit operations.
contract MpcExecutor is InboxUser, IPodExecutor64, IPodExecutor128, IPodExecutor256 {
    event GtResult(ctBool result, address cOwner);
    event AddResult(ctUint64 result, address cOwner);
    event Add128Result(ctUint128 result, address cOwner);
    event Add256Result(ctUint256 result, address cOwner);

    constructor(address _inbox) {
        setInbox(_inbox);
    }

    // --- IPodExecutor64 ---

    function add64(gtUint64 gtA, gtUint64 gtB, address cOwner) external onlyInbox {
        gtUint64 gtC = MpcCore.checkedAdd(gtA, gtB);
        _emitRespondU64(gtC, cOwner, true);
    }

    function sub64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.checkedSub(a, b), cOwner, false);
    }

    function mul64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.checkedMul(a, b), cOwner, false);
    }

    /// @dev COTI MPC requires `setPublic*` and `mul` in the same contract; do not pass `gt*` from another contract.
    function mul64FromPlain(uint64 a, uint64 b, address cOwner) external onlyInbox {
        gtUint64 ga = MpcCore.setPublic64(a);
        gtUint64 gb = MpcCore.setPublic64(b);
        _emitRespondU64(MpcCore.checkedMul(ga, gb), cOwner, false);
    }

    function div64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.div(a, b), cOwner, false);
    }

    function rem64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.rem(a, b), cOwner, false);
    }

    function and64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.and(a, b), cOwner, false);
    }

    function or64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.or(a, b), cOwner, false);
    }

    function xor64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.xor(a, b), cOwner, false);
    }

    function min64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.min(a, b), cOwner, false);
    }

    function max64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.max(a, b), cOwner, false);
    }

    function eq64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.eq(a, b), cOwner);
    }

    function ne64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.ne(a, b), cOwner);
    }

    function ge64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.ge(a, b), cOwner);
    }

    function gt64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.gt(a, b), cOwner);
    }

    function le64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.le(a, b), cOwner);
    }

    function lt64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.lt(a, b), cOwner);
    }

    /// @dev Plaintext `itBool` from user `encryptValue(0|1)` matches SBOOL validation but mux bit sense
    ///      is inverted vs SDK plaintext; swap branches so `1` selects `a` and `0` selects `b`.
    function mux64(gtBool bit, gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.mux(bit, b, a), cOwner, false);
    }

    function shl64(gtUint64 a, uint8 s, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.shl(a, s), cOwner, false);
    }

    function shr64(gtUint64 a, uint8 s, address cOwner) external onlyInbox {
        _emitRespondU64(MpcCore.shr(a, s), cOwner, false);
    }

    /// @dev Returns `abi.encode(uint256)` plaintext (not user ciphertext).
    function rand64(address) external onlyInbox {
        uint64 v = MpcCore.decrypt(MpcCore.rand64());
        _respondPlainUint256(uint256(v));
    }

    /// @dev Returns `abi.encode(uint256)` plaintext (not user ciphertext).
    function randBoundedBits64(uint8 numBits, address) external onlyInbox {
        uint64 v = MpcCore.decrypt(MpcCore.randBoundedBits64(numBits));
        _respondPlainUint256(uint256(v));
    }

    // --- IPodExecutor128 ---

    function add128(gtUint128 memory gtA, gtUint128 memory gtB, address cOwner) external onlyInbox {
        gtUint128 memory gtC = MpcCore.checkedAdd(gtA, gtB);
        _emitRespondU128(gtC, cOwner, true);
    }

    function sub128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondU128(MpcCore.checkedSub(a, b), cOwner, false);
    }

    /// @dev Uses wrapping `MpcCore.mul` (mod 2^128). `checkedMul` ends with `checkedSub(0, overflowLimbs)` which
    ///      can revert on COTI when high limbs are secret-shared zero even if the true product fits in 128 bits.
    function mul128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondU128(MpcCore.mul(a, b), cOwner, false);
    }

    /// @dev COTI MPC requires `setPublic*` and `mul` in the same contract; do not pass `gt*` from another contract.
    function mul128FromPlain(uint128 a, uint128 b, address cOwner) external onlyInbox {
        gtUint128 memory ga = MpcCore.setPublic128(a);
        gtUint128 memory gb = MpcCore.setPublic128(b);
        _emitRespondU128(MpcCore.mul(ga, gb), cOwner, false);
    }

    function and128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondU128(MpcCore.and(a, b), cOwner, false);
    }

    function or128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondU128(MpcCore.or(a, b), cOwner, false);
    }

    function xor128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondU128(MpcCore.xor(a, b), cOwner, false);
    }

    function min128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondU128(MpcCore.min(a, b), cOwner, false);
    }

    function max128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondU128(MpcCore.max(a, b), cOwner, false);
    }

    function eq128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.eq(a, b), cOwner);
    }

    function ne128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.ne(a, b), cOwner);
    }

    function ge128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.ge(a, b), cOwner);
    }

    function gt128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.gt(a, b), cOwner);
    }

    function le128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.le(a, b), cOwner);
    }

    function lt128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.lt(a, b), cOwner);
    }

    /// @dev See `mux64` — same `b,a` swap for client `itBool` ciphertexts.
    function mux128(gtBool bit, gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        _emitRespondU128(MpcCore.mux(bit, b, a), cOwner, false);
    }

    function shl128(gtUint128 memory a, uint8 s, address cOwner) external onlyInbox {
        _emitRespondU128(MpcCore.shl(a, s), cOwner, false);
    }

    function shr128(gtUint128 memory a, uint8 s, address cOwner) external onlyInbox {
        _emitRespondU128(MpcCore.shr(a, s), cOwner, false);
    }

    /// @dev Returns `abi.encode(uint256)` plaintext (not user ciphertext).
    function rand128(address) external onlyInbox {
        uint128 v = MpcCore.decrypt(MpcCore.rand128());
        _respondPlainUint256(uint256(v));
    }

    /// @dev Returns `abi.encode(uint256)` plaintext (not user ciphertext).
    /// @dev Do not use `MpcCore.randBoundedBits128` as-is: for `numBits <= 64` it calls `randBoundedBits64(0)` on the
    ///      high limb, and `RandBoundedBits(..., 0)` reverts on the COTI MPC precompile.
    function randBoundedBits128(uint8 numBits, address) external onlyInbox {
        uint128 v = MpcCore.decrypt(_randBoundedBits128Gt(numBits));
        _respondPlainUint256(uint256(v));
    }

    // --- IPodExecutor256 ---

    function add256(gtUint256 memory gtA, gtUint256 memory gtB, address cOwner) external onlyInbox {
        gtUint256 memory gtC = MpcCore.checkedAdd(gtA, gtB);
        _emitRespondU256(gtC, cOwner, true);
    }

    function sub256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondU256(MpcCore.checkedSub(a, b), cOwner, false);
    }

    /// @dev Wrapping multiply mod 2^256 via `MpcCore.mul`. On COTI, use `MpcExecutorCotiTest` + `MpcExecutorCotiProxyInbox`
    ///      (system test) to exercise this path with a minimal inbox `respond` stub.
    function mul256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondU256(MpcCore.mul(a, b), cOwner, false);
    }

    /// @dev COTI MPC requires `setPublic*` and `mul` in the same contract; do not pass `gt*` from another contract.
    function mul256FromPlain(uint256 a, uint256 b, address cOwner) external onlyInbox {
        gtUint256 memory ga = MpcCore.setPublic256(a);
        gtUint256 memory gb = MpcCore.setPublic256(b);
        _emitRespondU256(MpcCore.mul(ga, gb), cOwner, false);
    }

    function and256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondU256(MpcCore.and(a, b), cOwner, false);
    }

    function or256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondU256(MpcCore.or(a, b), cOwner, false);
    }

    function xor256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondU256(MpcCore.xor(a, b), cOwner, false);
    }

    function min256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondU256(MpcCore.min(a, b), cOwner, false);
    }

    function max256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondU256(MpcCore.max(a, b), cOwner, false);
    }

    function eq256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.eq(a, b), cOwner);
    }

    function ne256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.ne(a, b), cOwner);
    }

    function ge256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.ge(a, b), cOwner);
    }

    function gt256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.gt(a, b), cOwner);
    }

    function le256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.le(a, b), cOwner);
    }

    function lt256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondBool(MpcCore.lt(a, b), cOwner);
    }

    /// @dev See `mux64` — same `b,a` swap for client `itBool` ciphertexts.
    function mux256(gtBool bit, gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        _emitRespondU256(MpcCore.mux(bit, b, a), cOwner, false);
    }

    function shl256(gtUint256 memory a, uint8 s, address cOwner) external onlyInbox {
        _emitRespondU256(MpcCore.shl(a, s), cOwner, false);
    }

    function shr256(gtUint256 memory a, uint8 s, address cOwner) external onlyInbox {
        _emitRespondU256(MpcCore.shr(a, s), cOwner, false);
    }

    /// @dev Returns `abi.encode(uint256)` plaintext (not user ciphertext).
    function rand256(address) external onlyInbox {
        uint256 v = MpcCore.decrypt(MpcCore.rand256());
        _respondPlainUint256(v);
    }

    /// @dev Returns `abi.encode(uint256)` plaintext (not user ciphertext).
    /// @dev Same issue as 128-bit: `MpcCore.randBoundedBits256` calls `randBoundedBits128(0)` for the high half when
    ///      `numBits <= 128`, which hits `randBoundedBits64(0)` and reverts on COTI.
    function randBoundedBits256(uint8 numBits, address) external onlyInbox {
        uint256 v = MpcCore.decrypt(_randBoundedBits256Gt(numBits));
        _respondPlainUint256(v);
    }

    // --- internal ---

    /// @dev Split of 128-bit bounded random: unused high 64 bits must be `setPublic64(0)`, not `randBoundedBits64(0)`.
    function _randBoundedBits128Gt(uint8 numBits) private returns (gtUint128 memory gt) {
        require(numBits <= 128, "MpcExecutor: numBits");
        if (numBits == 0) {
            gt.low = MpcCore.setPublic64(0);
            gt.high = MpcCore.setPublic64(0);
            return gt;
        }
        uint8 lowBits = numBits > 64 ? uint8(64) : numBits;
        uint8 highBits = numBits > 64 ? numBits - 64 : uint8(0);
        gt.low = MpcCore.randBoundedBits64(lowBits);
        gt.high = highBits > 0 ? MpcCore.randBoundedBits64(highBits) : MpcCore.setPublic64(0);
    }

    /// @dev Split of 256-bit bounded random: unused high 128 bits must be `setPublic128(0)`, not `randBoundedBits128(0)`.
    function _randBoundedBits256Gt(uint8 numBits) private returns (gtUint256 memory gt) {
        require(numBits <= 256, "MpcExecutor: numBits");
        if (numBits == 0) {
            gt.low = MpcCore.setPublic128(0);
            gt.high = MpcCore.setPublic128(0);
            return gt;
        }
        uint8 lowBits = numBits > 128 ? uint8(128) : numBits;
        uint8 highBits = numBits > 128 ? numBits - 128 : uint8(0);
        gt.low = _randBoundedBits128Gt(lowBits);
        gt.high = highBits > 0 ? _randBoundedBits128Gt(highBits) : MpcCore.setPublic128(0);
    }

    function _respondPlainUint256(uint256 v) private {
        inbox.respond(abi.encode(v));
    }

    function _emitRespondU64(gtUint64 v, address cOwner, bool emitAddEvent) private {
        utUint64 memory combined = MpcCore.offBoardCombined(v, cOwner);
        if (emitAddEvent) {
            emit AddResult(combined.userCiphertext, cOwner);
        }
        inbox.respond(abi.encode(combined.userCiphertext));
    }

    function _emitRespondBool(gtBool v, address cOwner) private {
        utBool memory combined = MpcCore.offBoardCombined(v, cOwner);
        emit GtResult(combined.userCiphertext, cOwner);
        inbox.respond(abi.encode(combined.userCiphertext));
    }

    function _emitRespondU128(gtUint128 memory v, address cOwner, bool emitAdd128) private {
        utUint128 memory combined = MpcCore.offBoardCombined(v, cOwner);
        if (emitAdd128) {
            emit Add128Result(combined.userCiphertext, cOwner);
        }
        inbox.respond(abi.encode(combined.userCiphertext));
    }

    function _emitRespondU256(gtUint256 memory v, address cOwner, bool emitAdd256) private {
        utUint256 memory combined = MpcCore.offBoardCombined(v, cOwner);
        if (emitAdd256) {
            emit Add256Result(combined.userCiphertext, cOwner);
        }
        inbox.respond(abi.encode(combined.userCiphertext));
    }
}
