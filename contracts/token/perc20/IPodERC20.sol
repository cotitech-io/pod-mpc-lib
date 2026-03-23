// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

/**
 * @dev Interface of the COTI PoD (Privacy On Demand) ERC-20 standard.
 */
interface IPodERC20 {
    struct Allowance {
        ctUint256 ownerCiphertext;
        ctUint256 spenderCiphertext;
    }

    struct TransferRequested {
        address from;
        address to;
        bytes32 requestId;
    }

    /**
     * @dev Emitted when `senderValue/receiverValue` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `senderValue/receiverValue` may be zero.
     */
    event Transfer(
        address indexed from,
        address indexed to,
        ctUint256 senderValue,
        ctUint256 receiverValue
    );

    event TransferFailed(
        address indexed from,
        address indexed to,
        bytes errorMsg
    );

    struct ApprovalRequested {
        address owner;
        address spender;
        bytes32 requestId;
    }

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `ownerValue` and `spenderValue` are the new allowance encrypted with the respective users AES key.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        ctUint256 ownerValue,
        ctUint256 spenderValue
    );

    event RequestCallbackFailed(address from, address to, bytes32 requestId, bytes callbackData);
    event BalanceSynced(address account, ctUint256 amount);

    /**
     * @dev Returns the value of tokens in existence.
     *      For privacy, this implementation always returns 0; actual supply is stored encrypted.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account` encrypted with their AES key.
     */
    function balanceOf(
        address account
    ) external view returns (ctUint256 memory);

    /**
     * @dev Returns the value of tokens owned by `account` encrypted with their AES key.
     * and whether the balance is pending or not.
     */
    function balanceOfWithStatus(
        address account
    ) external view returns (ctUint256 memory, bool pending);

    /**
     * @dev Reencrypts the caller's balance using the AES key of `addr`.
     */
    // function setAccountEncryptionAddress(address addr) external returns (bytes32 requestId);

    /**
     * @dev Returns whether clear public `uint256` operations are currently enabled
     *      for this token (mint, burn, transfer, transferFrom, approve, transferAndCall
     *      variants that take plain amounts).
     */
    function publicAmountsEnabled() external view returns (bool);

    /**
     * @dev Enables or disables operations that use clear public `uint256` amounts
     *      (mint, burn, transfer, transferFrom, approve, transferAndCall with uint256).
     *      Intended for token admins that want to disallow public value usage and
     *      enforce encrypted-only flows.
     */
    function setPublicAmountsEnabled(bool enabled) external;

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns the request ID of the transfer.
     * Emits a {Transfer} event.
     */
    function transfer(
        address to,
        itUint256 calldata value
    ) external returns (bytes32 requestId);

    /**
     * @dev Moves a public `amount` of tokens from the caller's account to `to`.
     *
     * Returns the requestId of the transfer.
     *
     * Emits a {Transfer} event.
     */
    // function transfer(address to, uint256 amount) external returns (bytes32 requestId);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address owner,
        address spender
    ) external view returns (Allowance memory);

    function allowanceWithStatus(
        address owner,
        address spender
    ) external view returns (Allowance memory, bool pending);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns the request ID of the approval.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(
        address spender,
        itUint256 calldata value
    ) external returns (bytes32 requestId);

    /**
     * @dev Sets a public `amount` as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns the request ID of the approval.
     *
     * Emits an {Approval} event.
     */
    // function approve(address spender, uint256 amount) external returns (bytes32 requestId);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Reverts if the transfer fails. On success, returns an encrypted true.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        itUint256 calldata value
    ) external returns (bytes32 requestId);

    /**
     * @dev Moves a public `amount` of tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Reverts if the transfer fails. Returns true on success.
     *
     * Emits a {Transfer} event.
     */
    // function transferFrom(address from, address to, uint256 amount) external returns (bytes32 requestId);

    /**
     * @dev Moves a garbled-text `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's allowance.
     *
     * Reverts if the transfer fails. On success, returns an encrypted true.
     * 
     * NOT SUPPORTED
     *
     * Emits a {Transfer} event.
     */
    // function transferFromGT(address from, address to, gtUint256 value) external returns (gtBool);

    function transferAndCall(
        address to,
        itUint256 calldata amount,
        bytes calldata data
    ) external returns (bytes32 requestId);

    /**
     * @dev Creates `amount` public tokens and assigns them to `to`, increasing the total supply.
     *
     * Returns a boolean value indicating whether the operation succeeded (decrypted from gtBool).
     */
    // function mint(address to, uint256 amount) external returns (bool);

    /**
     * @dev Creates `amount` input-text (encrypted) tokens and assigns them to `to`, increasing the total supply.
     *
     * Returns an encrypted boolean value indicating whether the operation succeeded.
     */
    // function mint(address to, itUint256 calldata amount) external returns (gtBool);

    /**
     * @dev Creates `amount` garbled-text tokens and assigns them to `to` without re-wrapping.
     * 
     * NOT SUPPORTED
     *
     * Returns an encrypted boolean value indicating whether the operation succeeded.
     */
    // function mintGt(address to, gtUint256 amount) external returns (gtBool);

    /**
     * @dev Destroys `amount` public tokens from the caller.
     *
     * Returns a boolean value indicating whether the operation succeeded (decrypted from gtBool).
     */
    // function burn(uint256 amount) external returns (bool);

    /**
     * @dev Destroys `amount` input-text (encrypted) tokens from the caller.
     *
     * Returns an encrypted boolean value indicating whether the operation succeeded.
     * Callers must check or decrypt the return value; this variant does not revert on failure.
     */
    function burn(itUint256 calldata amount) external returns (bytes32 requestId);

    /**
     * @dev Destroys `amount` garbled-text tokens from the caller without re-wrapping.
     * 
     * NOT SUPPORTED
     *
     * Returns an encrypted boolean value indicating whether the operation succeeded.
     * Callers must check or decrypt the return value; this variant does not revert on failure.
     */
    // function burnGt(gtUint256 amount) external returns (gtBool);

    function syncBalances(address[] calldata accounts) external returns (bytes32 requestId);
}