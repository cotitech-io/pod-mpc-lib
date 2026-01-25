// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

/**
 * This interface is used to define the common MPC methods 
 */
interface ICommonMpcMethods {
    function add(gtUint64 a, gtUint64 b, address cOwner) external;
}
