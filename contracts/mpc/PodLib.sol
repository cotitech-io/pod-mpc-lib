// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./PodLib64.sol";
import "./PodLib128.sol";
import "./PodLib256.sol";

/**
 * @title PodLib
 * @notice Full POD MPC surface: 64-, 128-, and 256-bit operations (multiple inheritance over shared PodLibBase).
 */
abstract contract PodLib is PodLib64, PodLib128, PodLib256 {}
