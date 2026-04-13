// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../InboxUser.sol";

/// @title PrivateTreasuryApprovalCotiFailureHarness
/// @notice Test-only COTI target that forces the treasury-approval source contract down its error callbacks.
contract PrivateTreasuryApprovalCotiFailureHarness is InboxUser {
    constructor(address _inbox) {
        setInbox(_inbox);
    }

    function registerProposal(uint256 proposalId, uint256, uint256) external onlyInbox {
        inbox.raise(abi.encode(proposalId, bytes("PrivateTreasuryApprovalCotiFailureHarness: register failed")));
    }

    function castApproval(uint256 proposalId, address voter, gtBool) external onlyInbox {
        inbox.raise(abi.encode(proposalId, voter, bytes("PrivateTreasuryApprovalCotiFailureHarness: approval failed")));
    }

    function finalizeProposal(uint256 proposalId, address) external onlyInbox {
        inbox.raise(abi.encode(proposalId, bytes("PrivateTreasuryApprovalCotiFailureHarness: finalize failed")));
    }
}
