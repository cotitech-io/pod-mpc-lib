// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../InboxUser.sol";

/// @title PrivateBudgetGuardCotiFailureHarness
/// @notice Test-only COTI target that forces the budget-guard source contract down its error callbacks.
contract PrivateBudgetGuardCotiFailureHarness is InboxUser {
    constructor(address _inbox) {
        setInbox(_inbox);
    }

    function registerBudget(address owner, gtUint64) external onlyInbox {
        inbox.raise(abi.encode(owner, bytes("PrivateBudgetGuardCotiFailureHarness: register failed")));
    }

    function checkAndSpend(address owner, gtUint64) external onlyInbox {
        inbox.raise(abi.encode(owner, bytes("PrivateBudgetGuardCotiFailureHarness: spend failed")));
    }
}
