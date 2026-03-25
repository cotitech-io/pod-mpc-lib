// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";


/**
 * @title PodErc20CotiSideCodecHarness
 * @notice Pure helpers to build and parse payloads aligned with {PodERC20} callbacks and {PodErc20CotiSide} `respond` / `raise`
 *         encodings. Intended for Hardhat/Foundry tests—not for production deployment.
 */
contract PodErc20CotiSideCodecHarness {
    // --- Constants ---

    bytes4 public constant TRANSFER_ERROR = bytes4(keccak256("transferError(bytes)"));
    bytes4 public constant APPROVE_ERROR = bytes4(keccak256("approveError(bytes)"));
    bytes4 public constant SYNC_BALANCES_ERROR = bytes4(keccak256("syncBalancesError(bytes)"));

    // --- Transfer success payload (matches `PodERC20.transferCallback` / {PodErc20CotiSide} transfer path) ---

    /**
     * @notice ABI-encodes the seven-field tuple consumed by `PodERC20.transferCallback`.
     * @param nonce Monotonic nonce from COTI; PoD applies balance updates only when newer than {PodERC20.balanceNonces}.
     */
    function encodeTransferCallbackPayload(
        address from,
        ctUint256 memory newBalanceFrom,
        ctUint256 memory senderValue,
        address to,
        ctUint256 memory newBalanceTo,
        ctUint256 memory receiverValue,
        uint256 nonce
    ) external pure returns (bytes memory) {
        return abi.encode(from, newBalanceFrom, senderValue, to, newBalanceTo, receiverValue, nonce);
    }

    /// @notice Decodes the tuple from {encodeTransferCallbackPayload}.
    function decodeTransferCallbackPayload(bytes calldata data)
        external
        pure
        returns (
            address from,
            ctUint256 memory newBalanceFrom,
            ctUint256 memory senderValue,
            address to,
            ctUint256 memory newBalanceTo,
            ctUint256 memory receiverValue,
            uint256 nonce
        )
    {
        return abi.decode(data, (address, ctUint256, ctUint256, address, ctUint256, ctUint256, uint256));
    }

    // --- Approve success payload ---

    /// @notice Same tuple as `PodERC20.approveCallback`.
    function encodeApproveCallbackPayload(
        address owner,
        ctUint256 memory ownerAmount,
        address spender,
        ctUint256 memory spenderAmount
    ) external pure returns (bytes memory) {
        return abi.encode(owner, ownerAmount, spender, spenderAmount);
    }

    /// @notice Decodes the tuple from {encodeApproveCallbackPayload}.
    function decodeApproveCallbackPayload(bytes calldata data)
        external
        pure
        returns (address owner, ctUint256 memory ownerAmount, address spender, ctUint256 memory spenderAmount)
    {
        return abi.decode(data, (address, ctUint256, address, ctUint256));
    }

    // --- Sync success payload ---

    /**
     * @notice Same tuple as `PodERC20.syncBalancesCallback` receives after COTI `respond`.
     * @dev **Gotcha:** must include `nonce`; omitting it will not match production decoding.
     */
    function encodeSyncBalancesCallbackPayload(
        address[] calldata accounts,
        ctUint256[] calldata amounts,
        uint256 nonce
    ) external pure returns (bytes memory) {
        return abi.encode(accounts, amounts, nonce);
    }

    /// @notice Decodes `(accounts, amounts, nonce)` from {encodeSyncBalancesCallbackPayload}.
    function decodeSyncBalancesCallbackPayload(bytes calldata data)
        external
        pure
        returns (address[] memory accounts, ctUint256[] memory amounts, uint256 nonce)
    {
        return abi.decode(data, (address[], ctUint256[], uint256));
    }

    // --- Error inner payloads ---

    /// @notice Inner `bytes` passed to `transferError(bytes)` / `approveError(bytes)` after ABI wrapping.
    function encodeTransferOrApproveErrorTuple(address a, address b, bytes calldata err)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(a, b, err);
    }

    /// @notice Decodes the `(a, b, err)` tuple from {encodeTransferOrApproveErrorTuple}.
    function decodeTransferOrApproveErrorTuple(bytes calldata data)
        external
        pure
        returns (address a, address b, bytes memory err)
    {
        return abi.decode(data, (address, address, bytes));
    }

    /// @notice Full calldata as `InboxBase` raw `MpcMethodCall.data`: `abi.encodeWithSelector(selector, inner)`.
    function wrapErrorCall(bytes4 selector, bytes calldata inner) external pure returns (bytes memory) {
        return abi.encodeWithSelector(selector, inner);
    }

    /// @notice `require` round-trip: reverts if encode/decode diverges (for tests).
    function assertTransferCallbackRoundTrip(
        address from,
        ctUint256 memory c0,
        ctUint256 memory c1,
        address to,
        ctUint256 memory c2,
        ctUint256 memory c3,
        uint256 nonce
    ) external pure {
        bytes memory data = abi.encode(from, c0, c1, to, c2, c3, nonce);
        (
            address f,
            ctUint256 memory n0,
            ctUint256 memory n1,
            address t,
            ctUint256 memory n2,
            ctUint256 memory n3,
            uint256 n
        ) = abi.decode(data, (address, ctUint256, ctUint256, address, ctUint256, ctUint256, uint256));
        require(f == from && t == to && n == nonce, "addr/nonce");
        require(_ctEq(c0, n0) && _ctEq(c1, n1) && _ctEq(c2, n2) && _ctEq(c3, n3), "ct");
    }

    function _ctEq(ctUint256 memory a, ctUint256 memory b) private pure returns (bool) {
        return ctUint64.unwrap(a.high.high) == ctUint64.unwrap(b.high.high)
            && ctUint64.unwrap(a.high.low) == ctUint64.unwrap(b.high.low)
            && ctUint64.unwrap(a.low.high) == ctUint64.unwrap(b.low.high)
            && ctUint64.unwrap(a.low.low) == ctUint64.unwrap(b.low.low);
    }
}
