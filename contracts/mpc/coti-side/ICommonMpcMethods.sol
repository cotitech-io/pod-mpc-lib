// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

/**
 * This interface is used to define the common MPC methods. To be implemented
 * on the COTI side. On the client side, user must use this method signature.
 * Even though they are passing itUnit64. This will be the main gotcha
 */
interface ICommonMpcMethods {
    /// @notice Add two encrypted values and emit/return the result to the owner.
    /// @param a Encrypted input a.
    /// @param b Encrypted input b.
    /// @param cOwner Owner of the result ciphertext.
    function add(gtUint64 a, gtUint64 b, address cOwner) external;

    /// @notice Compare two encrypted values and emit/return the result to the owner.
    /// @param a Encrypted input a.
    /// @param b Encrypted input b.
    /// @param cOwner Owner of the result ciphertext.
    function gt(gtUint64 a, gtUint64 b, address cOwner) external;

    /// @notice Add two 128-bit encrypted values and emit/return the result to the owner.
    /// @param a Encrypted input a (gtUint128).
    /// @param b Encrypted input b (gtUint128).
    /// @param cOwner Owner of the result ciphertext.
    function add128(gtUint128 memory a, gtUint128 memory b, address cOwner) external;

    /// @notice Add two 256-bit encrypted values and emit/return the result to the owner.
    /// @param a Encrypted input a (gtUint256).
    /// @param b Encrypted input b (gtUint256).
    /// @param cOwner Owner of the result ciphertext.
    function add256(gtUint256 memory a, gtUint256 memory b, address cOwner) external;
}
