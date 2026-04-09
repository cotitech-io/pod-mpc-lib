// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../InboxUser.sol";

/// @title PrivateBudgetGuardCoti
/// @notice COTI-side private budget ledger for the PrivateBudgetGuard PoD example.
contract PrivateBudgetGuardCoti is InboxUser {
    event BudgetStored(address indexed owner, ctUint64 remainingBudget);
    event SpendChecked(address indexed owner, ctBool approved, ctUint64 remainingBudget);

    mapping(address => ctUint64) public budgetOf;
    mapping(address => bool) public isBudgetRegistered;

    constructor(address _inbox) {
        setInbox(_inbox);
    }

    /// @notice Stores the user's budget in remote state and returns an offboarded view for the owner.
    function registerBudget(address owner, gtUint64 budget) external onlyInbox {
        if (owner == address(0)) {
            _raiseBudgetError(owner, bytes("PrivateBudgetGuardCoti: zero owner"));
            return;
        }

        budgetOf[owner] = MpcCore.offBoard(budget);
        isBudgetRegistered[owner] = true;

        ctUint64 ownerBudget = MpcCore.offBoardToUser(budget, owner);
        emit BudgetStored(owner, ownerBudget);
        inbox.respond(abi.encode(owner, ownerBudget));
    }

    /// @notice Evaluates whether `amount` fits inside the stored budget and returns approval + remaining budget.
    /// @dev The approval bit is decrypted on the COTI side for control flow only; the actual amount and budget remain encrypted.
    function checkAndSpend(address owner, gtUint64 amount) external onlyInbox {
        if (owner == address(0)) {
            _raiseBudgetError(owner, bytes("PrivateBudgetGuardCoti: zero owner"));
            return;
        }
        if (!isBudgetRegistered[owner]) {
            _raiseBudgetError(owner, bytes("PrivateBudgetGuardCoti: budget not registered"));
            return;
        }

        gtUint64 currentBudget = MpcCore.onBoard(budgetOf[owner]);
        gtBool approved = MpcCore.le(amount, currentBudget);
        bool isApproved = MpcCore.decrypt(approved);

        gtUint64 nextBudget;
        if (isApproved) {
            nextBudget = MpcCore.sub(currentBudget, amount);
        } else {
            nextBudget = currentBudget;
        }

        budgetOf[owner] = MpcCore.offBoard(nextBudget);

        ctBool approvedCt = MpcCore.offBoardToUser(approved, owner);
        ctUint64 remainingCt = MpcCore.offBoardToUser(nextBudget, owner);
        emit SpendChecked(owner, approvedCt, remainingCt);
        inbox.respond(abi.encode(owner, approvedCt, remainingCt));
    }

    function _raiseBudgetError(address owner, bytes memory reason) private {
        inbox.raise(abi.encode(owner, reason));
    }
}
