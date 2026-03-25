// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

/**
 * @title IPodErc20CotiSide
 * @notice Entry points the COTI inbox invokes for a paired {PodERC20}: balance/allowance ciphertext on-chain, MPC garbling in memory, and `respond`/`raise` wiring.
 * @dev Implementations must restrict callers to the inbox and to the configured remote `PodERC20`. `transferFrom` does not carry
 *      `msg.sender` as spender on this chain—allowance must be enforced before the cross-chain message is sent.
 */
interface IPodErc20CotiSide {
    /**
     * @notice Mints plain `amount` into balance ciphertext storage for `to` (typically owner-only for bridge or test setup).
     * @dev Does not automatically update PoD ciphertext; use {syncBalances} on `PodERC20` after minting if mirrors must match.
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice For each account, `onBoard`s stored balance ciphertext, `offBoardToUser`s to that address, and `respond`s with `(addresses, amounts, nonce)`.
     * @dev **Gotcha:** empty `accounts` should be rejected by the implementation; otherwise PoD may receive useless callbacks.
     */
    function syncBalances(address[] calldata accounts) external;

    /**
     * @notice Moves `value` garbled tokens from `from` to `to` if balance suffices, then `respond`s with the PoD transfer tuple.
     * @dev **Gotcha:** locks on PoD are tracked separately; this function assumes the inbox message is well-formed.
     */
    function transfer(address from, address to, gtUint256 calldata value) external;

    /**
     * @notice Same MPC move as {transfer}; spender allowance is not checked here—`PodERC20` / policy must do that before sending.
     * @dev **Gotcha:** without off-chain or PoD-side enforcement, `transferFrom` is equivalent to `transfer` on COTI.
     */
    function transferFrom(address from, address to, gtUint256 calldata value) external;

    /**
     * @notice Sets garbled allowance and `respond`s with owner- and spender-specific ciphertext of the same allowance amount.
     * @dev On invalid addresses the implementation should `raise` rather than revert if you need PoD `approveError` symmetry.
     */
    function approve(address owner, address spender, gtUint256 calldata value) external;

    /**
     * @notice Subtracts `value` from `from` and responds with a burn-shaped tuple (`to == 0`, zero ciphertexts for receiver side).
     */
    function burn(address from, gtUint256 calldata value) external;
}
