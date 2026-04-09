// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

/// @title IPrivateBudgetGuardCoti
/// @notice COTI-side interface for the PrivateBudgetGuard example.
interface IPrivateBudgetGuardCoti {
    function registerBudget(address owner, gtUint64 budget) external;

    function checkAndSpend(address owner, gtUint64 amount) external;
}
