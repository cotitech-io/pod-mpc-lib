// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../InboxUser.sol";

/// @title PrivateTreasuryApprovalCoti
/// @notice COTI-side encrypted tally store for the PrivateTreasuryApproval example.
contract PrivateTreasuryApprovalCoti is InboxUser {
    event ProposalStored(uint256 indexed proposalId);
    event ApprovalTallied(uint256 indexed proposalId, address indexed voter, ctBool recordedVote);
    event ProposalResolved(uint256 indexed proposalId, bool approved, ctUint64 yesVotes, ctUint64 noVotes);

    mapping(uint256 => ctUint64) public yesVotesOf;
    mapping(uint256 => ctUint64) public noVotesOf;
    mapping(uint256 => uint64) public thresholdOf;
    mapping(uint256 => uint64) public deadlineOf;
    mapping(uint256 => bool) public isProposalRegistered;
    mapping(uint256 => bool) public isProposalFinalized;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    constructor(address _inbox) {
        setInbox(_inbox);
    }

    function registerProposal(uint256 proposalId, uint256 threshold, uint256 deadline) external onlyInbox {
        if (proposalId == 0) {
            _raiseRegisterError(proposalId, bytes("PrivateTreasuryApprovalCoti: zero proposal"));
            return;
        }
        if (isProposalRegistered[proposalId]) {
            _raiseRegisterError(proposalId, bytes("PrivateTreasuryApprovalCoti: already registered"));
            return;
        }
        if (threshold == 0 || threshold > type(uint64).max) {
            _raiseRegisterError(proposalId, bytes("PrivateTreasuryApprovalCoti: invalid threshold"));
            return;
        }
        if (deadline == 0 || deadline > type(uint64).max) {
            _raiseRegisterError(proposalId, bytes("PrivateTreasuryApprovalCoti: invalid deadline"));
            return;
        }

        gtUint64 zero = MpcCore.setPublic64(0);
        yesVotesOf[proposalId] = MpcCore.offBoard(zero);
        noVotesOf[proposalId] = MpcCore.offBoard(zero);
        thresholdOf[proposalId] = uint64(threshold);
        deadlineOf[proposalId] = uint64(deadline);
        isProposalRegistered[proposalId] = true;

        emit ProposalStored(proposalId);
        inbox.respond(abi.encode(proposalId));
    }

    function castApproval(uint256 proposalId, address voter, gtBool support) external onlyInbox {
        if (proposalId == 0) {
            _raiseApprovalError(proposalId, voter, bytes("PrivateTreasuryApprovalCoti: zero proposal"));
            return;
        }
        if (voter == address(0)) {
            _raiseApprovalError(proposalId, voter, bytes("PrivateTreasuryApprovalCoti: zero voter"));
            return;
        }
        if (!isProposalRegistered[proposalId]) {
            _raiseApprovalError(proposalId, voter, bytes("PrivateTreasuryApprovalCoti: proposal not registered"));
            return;
        }
        if (isProposalFinalized[proposalId]) {
            _raiseApprovalError(proposalId, voter, bytes("PrivateTreasuryApprovalCoti: proposal finalized"));
            return;
        }
        if (hasVoted[proposalId][voter]) {
            _raiseApprovalError(proposalId, voter, bytes("PrivateTreasuryApprovalCoti: already voted"));
            return;
        }

        gtUint64 zero = MpcCore.setPublic64(0);
        gtUint64 one = MpcCore.setPublic64(1);
        gtUint64 currentYes = MpcCore.onBoard(yesVotesOf[proposalId]);
        gtUint64 currentNo = MpcCore.onBoard(noVotesOf[proposalId]);

        // MpcCore.mux selects the second branch for encrypted plaintext `1`,
        // so pass `(zero, one)` to preserve the intuitive 1=>yes and 0=>no mapping.
        gtUint64 yesIncrement = MpcCore.mux(support, zero, one);
        gtUint64 noIncrement = MpcCore.mux(support, one, zero);
        gtUint64 nextYes = MpcCore.checkedAdd(currentYes, yesIncrement);
        gtUint64 nextNo = MpcCore.checkedAdd(currentNo, noIncrement);

        yesVotesOf[proposalId] = MpcCore.offBoard(nextYes);
        noVotesOf[proposalId] = MpcCore.offBoard(nextNo);
        hasVoted[proposalId][voter] = true;

        ctBool recordedVote = MpcCore.offBoardToUser(support, voter);
        emit ApprovalTallied(proposalId, voter, recordedVote);
        inbox.respond(abi.encode(proposalId, voter, recordedVote));
    }

    function finalizeProposal(uint256 proposalId, address resultOwner) external onlyInbox {
        if (proposalId == 0) {
            _raiseFinalizeError(proposalId, bytes("PrivateTreasuryApprovalCoti: zero proposal"));
            return;
        }
        if (resultOwner == address(0)) {
            _raiseFinalizeError(proposalId, bytes("PrivateTreasuryApprovalCoti: zero result owner"));
            return;
        }
        if (!isProposalRegistered[proposalId]) {
            _raiseFinalizeError(proposalId, bytes("PrivateTreasuryApprovalCoti: proposal not registered"));
            return;
        }
        if (isProposalFinalized[proposalId]) {
            _raiseFinalizeError(proposalId, bytes("PrivateTreasuryApprovalCoti: proposal finalized"));
            return;
        }
        gtUint64 yesVotes = MpcCore.onBoard(yesVotesOf[proposalId]);
        gtUint64 noVotes = MpcCore.onBoard(noVotesOf[proposalId]);
        gtBool approvedGt = MpcCore.ge(yesVotes, MpcCore.setPublic64(thresholdOf[proposalId]));
        bool approved = MpcCore.decrypt(approvedGt);

        isProposalFinalized[proposalId] = true;

        ctUint64 yesVotesCt = MpcCore.offBoardToUser(yesVotes, resultOwner);
        ctUint64 noVotesCt = MpcCore.offBoardToUser(noVotes, resultOwner);
        emit ProposalResolved(proposalId, approved, yesVotesCt, noVotesCt);
        inbox.respond(abi.encode(proposalId, approved, yesVotesCt, noVotesCt));
    }

    function _raiseRegisterError(uint256 proposalId, bytes memory reason) private {
        inbox.raise(abi.encode(proposalId, reason));
    }

    function _raiseApprovalError(uint256 proposalId, address voter, bytes memory reason) private {
        inbox.raise(abi.encode(proposalId, voter, reason));
    }

    function _raiseFinalizeError(uint256 proposalId, bytes memory reason) private {
        inbox.raise(abi.encode(proposalId, reason));
    }
}
