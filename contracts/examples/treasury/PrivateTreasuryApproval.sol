// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../../IInbox.sol";
import "../../mpc/PodLibBase.sol";
import "../../mpccodec/MpcAbiCodec.sol";
import "./IPrivateTreasuryApprovalCoti.sol";

/// @title PrivateTreasuryApproval
/// @notice Source-chain treasury payout example with private committee approvals on COTI.
contract PrivateTreasuryApproval is PodLibBase, ReentrancyGuard {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    struct PayoutProposal {
        address recipient;
        address asset;
        uint256 amount;
        bytes32 descriptionHash;
        uint64 deadline;
        uint64 threshold;
        bool exists;
        bool registered;
        bool finalized;
        bool approved;
        bool executed;
    }

    error UnsupportedAsset(address asset);
    error InvalidRecipient();
    error InvalidAmount();
    error InvalidDeadline(uint64 deadline);
    error InvalidThreshold(uint64 threshold, uint256 approverCount);
    error DuplicateApprover(address approver);
    error ProposalUnknown(uint256 proposalId);
    error ProposalAlreadyRegistered(uint256 proposalId);
    error ProposalRegisterPending(uint256 proposalId, bytes32 requestId);
    error ProposalNotRegistered(uint256 proposalId);
    error ProposalAlreadyFinalized(uint256 proposalId);
    error VotingClosed(uint256 proposalId);
    error VotingStillOpen(uint256 proposalId, uint64 deadline);
    error NotEligibleApprover(uint256 proposalId, address voter);
    error ApprovalAlreadyPending(uint256 proposalId, address voter, bytes32 requestId);
    error FinalizeAlreadyPending(uint256 proposalId, bytes32 requestId);
    error ApprovalCallbacksPending(uint256 proposalId, uint256 pendingCount);
    error ProposalNotApproved(uint256 proposalId);
    error ProposalAlreadyExecuted(uint256 proposalId);
    error EthTransferFailed(address recipient, uint256 amount);

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed recipient,
        uint256 amount,
        uint64 deadline,
        uint64 threshold
    );
    event ProposalRegistrationRequested(uint256 indexed proposalId, bytes32 indexed requestId);
    event ProposalRegistered(uint256 indexed proposalId, bytes32 indexed requestId);
    event ProposalRegistrationFailed(uint256 indexed proposalId, bytes32 indexed requestId, bytes reason);
    event ApprovalRequested(uint256 indexed proposalId, address indexed voter, bytes32 indexed requestId);
    event ApprovalRecorded(uint256 indexed proposalId, address indexed voter, bytes32 indexed requestId, ctBool recordedVote);
    event ApprovalFailed(uint256 indexed proposalId, address indexed voter, bytes32 indexed requestId, bytes reason);
    event FinalizeRequested(uint256 indexed proposalId, bytes32 indexed requestId);
    event ProposalFinalized(
        uint256 indexed proposalId, bytes32 indexed requestId, bool approved, ctUint64 yesVotes, ctUint64 noVotes
    );
    event FinalizeFailed(uint256 indexed proposalId, bytes32 indexed requestId, bytes reason);
    event ProposalExecuted(uint256 indexed proposalId, address indexed recipient, uint256 amount);
    event PendingRegisterCleared(uint256 indexed proposalId, bytes32 previousRequestId);
    event PendingApprovalCleared(uint256 indexed proposalId, address indexed voter, bytes32 previousRequestId);
    event PendingFinalizeCleared(uint256 indexed proposalId, bytes32 previousRequestId);

    uint256 public nextProposalId = 1;

    mapping(uint256 => PayoutProposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public isEligibleApprover;
    mapping(uint256 => mapping(address => bytes32)) public pendingApprovalRequestIdOf;
    mapping(uint256 => bytes32) public pendingRegisterRequestIdOf;
    mapping(uint256 => bytes32) public pendingFinalizeRequestIdOf;
    mapping(uint256 => uint256) public pendingApprovalCountOf;
    mapping(uint256 => mapping(address => ctBool)) public recordedVoteReceiptOf;
    mapping(uint256 => ctUint64) public encryptedYesVotesOf;
    mapping(uint256 => ctUint64) public encryptedNoVotesOf;

    constructor(address _inbox) PodLibBase(msg.sender) {
        setInbox(_inbox);
    }

    function createProposal(
        address recipient,
        address asset,
        uint256 amount,
        bytes32 descriptionHash,
        uint64 deadline,
        uint64 threshold,
        address[] calldata approvers,
        uint256 callbackFeeLocalWei
    ) external payable onlyOwner nonReentrant returns (uint256 proposalId, bytes32 requestId) {
        if (recipient == address(0)) revert InvalidRecipient();
        if (asset != address(0)) revert UnsupportedAsset(asset);
        if (amount == 0) revert InvalidAmount();
        if (deadline <= block.timestamp) revert InvalidDeadline(deadline);
        if (threshold == 0 || threshold > approvers.length) revert InvalidThreshold(threshold, approvers.length);

        proposalId = nextProposalId++;
        PayoutProposal storage proposal = proposals[proposalId];
        proposal.recipient = recipient;
        proposal.asset = asset;
        proposal.amount = amount;
        proposal.descriptionHash = descriptionHash;
        proposal.deadline = deadline;
        proposal.threshold = threshold;
        proposal.exists = true;

        uint256 approverCount = approvers.length;
        for (uint256 i = 0; i < approverCount; ++i) {
            address approver = approvers[i];
            if (approver == address(0)) revert InvalidRecipient();
            for (uint256 j = 0; j < i; ++j) {
                if (approvers[j] == approver) revert DuplicateApprover(approver);
            }
            isEligibleApprover[proposalId][approver] = true;
        }

        emit ProposalCreated(proposalId, recipient, amount, deadline, threshold);
        requestId = _registerProposalRemote(proposalId, callbackFeeLocalWei, msg.value);
    }

    function registerProposalRemote(uint256 proposalId, uint256 callbackFeeLocalWei)
        external
        payable
        onlyOwner
        nonReentrant
        returns (bytes32 requestId)
    {
        requestId = _registerProposalRemote(proposalId, callbackFeeLocalWei, msg.value);
    }

    function castApproval(uint256 proposalId, itBool calldata support, uint256 callbackFeeLocalWei)
        external
        payable
        nonReentrant
        returns (bytes32 requestId)
    {
        PayoutProposal storage proposal = _requireActiveProposal(proposalId);
        if (!isEligibleApprover[proposalId][msg.sender]) {
            revert NotEligibleApprover(proposalId, msg.sender);
        }
        if (pendingRegisterRequestIdOf[proposalId] != bytes32(0)) {
            revert ProposalRegisterPending(proposalId, pendingRegisterRequestIdOf[proposalId]);
        }
        bytes32 pendingApproval = pendingApprovalRequestIdOf[proposalId][msg.sender];
        if (pendingApproval != bytes32(0)) {
            revert ApprovalAlreadyPending(proposalId, msg.sender, pendingApproval);
        }
        if (block.timestamp >= proposal.deadline) {
            revert VotingClosed(proposalId);
        }

        IInbox.MpcMethodCall memory methodCall = MpcAbiCodec.create(IPrivateTreasuryApprovalCoti.castApproval.selector, 3)
            .addArgument(proposalId)
            .addArgument(msg.sender)
            .addArgument(support)
            .build();

        requestId = _sendTwoWayWithFee(
            msg.value,
            callbackFeeLocalWei,
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            PrivateTreasuryApproval.onApprovalRecorded.selector,
            PrivateTreasuryApproval.onApprovalError.selector
        );

        pendingApprovalRequestIdOf[proposalId][msg.sender] = requestId;
        unchecked {
            pendingApprovalCountOf[proposalId] += 1;
        }
        emit ApprovalRequested(proposalId, msg.sender, requestId);
    }

    function finalizeProposal(uint256 proposalId, uint256 callbackFeeLocalWei)
        external
        payable
        nonReentrant
        returns (bytes32 requestId)
    {
        PayoutProposal storage proposal = _requireExistingProposal(proposalId);
        if (!proposal.registered) revert ProposalNotRegistered(proposalId);
        if (proposal.finalized) revert ProposalAlreadyFinalized(proposalId);
        if (block.timestamp < proposal.deadline) revert VotingStillOpen(proposalId, proposal.deadline);
        if (pendingApprovalCountOf[proposalId] != 0) {
            revert ApprovalCallbacksPending(proposalId, pendingApprovalCountOf[proposalId]);
        }

        bytes32 pendingFinalize = pendingFinalizeRequestIdOf[proposalId];
        if (pendingFinalize != bytes32(0)) {
            revert FinalizeAlreadyPending(proposalId, pendingFinalize);
        }

        IInbox.MpcMethodCall memory methodCall =
            MpcAbiCodec.create(IPrivateTreasuryApprovalCoti.finalizeProposal.selector, 2)
                .addArgument(proposalId)
                .addArgument(owner())
                .build();

        requestId = _sendTwoWayWithFee(
            msg.value,
            callbackFeeLocalWei,
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            PrivateTreasuryApproval.onProposalFinalized.selector,
            PrivateTreasuryApproval.onFinalizeError.selector
        );

        pendingFinalizeRequestIdOf[proposalId] = requestId;
        emit FinalizeRequested(proposalId, requestId);
    }

    function executeProposal(uint256 proposalId) external nonReentrant {
        PayoutProposal storage proposal = _requireExistingProposal(proposalId);
        if (!proposal.finalized || !proposal.approved) revert ProposalNotApproved(proposalId);
        if (proposal.executed) revert ProposalAlreadyExecuted(proposalId);
        if (proposal.asset != address(0)) revert UnsupportedAsset(proposal.asset);

        proposal.executed = true;
        (bool ok,) = proposal.recipient.call{value: proposal.amount}("");
        if (!ok) revert EthTransferFailed(proposal.recipient, proposal.amount);

        emit ProposalExecuted(proposalId, proposal.recipient, proposal.amount);
    }

    function clearPendingRegister(uint256 proposalId) external onlyOwner {
        bytes32 previousRequestId = pendingRegisterRequestIdOf[proposalId];
        pendingRegisterRequestIdOf[proposalId] = bytes32(0);
        emit PendingRegisterCleared(proposalId, previousRequestId);
    }

    function clearPendingApproval(uint256 proposalId, address voter) external onlyOwner {
        bytes32 previousRequestId = pendingApprovalRequestIdOf[proposalId][voter];
        if (previousRequestId != bytes32(0) && pendingApprovalCountOf[proposalId] != 0) {
            unchecked {
                pendingApprovalCountOf[proposalId] -= 1;
            }
        }
        pendingApprovalRequestIdOf[proposalId][voter] = bytes32(0);
        emit PendingApprovalCleared(proposalId, voter, previousRequestId);
    }

    function clearPendingFinalize(uint256 proposalId) external onlyOwner {
        bytes32 previousRequestId = pendingFinalizeRequestIdOf[proposalId];
        pendingFinalizeRequestIdOf[proposalId] = bytes32(0);
        emit PendingFinalizeCleared(proposalId, previousRequestId);
    }

    function onProposalRegistered(bytes memory data) external onlyInbox {
        uint256 proposalId = abi.decode(data, (uint256));
        bytes32 sourceRequestId = _currentSourceRequestId();
        if (pendingRegisterRequestIdOf[proposalId] == sourceRequestId) {
            pendingRegisterRequestIdOf[proposalId] = bytes32(0);
        }
        proposals[proposalId].registered = true;
        emit ProposalRegistered(proposalId, sourceRequestId);
    }

    function onApprovalRecorded(bytes memory data) external onlyInbox {
        (uint256 proposalId, address voter, ctBool recordedVote) = abi.decode(data, (uint256, address, ctBool));
        bytes32 sourceRequestId = _currentSourceRequestId();
        if (voter != address(0) && pendingApprovalRequestIdOf[proposalId][voter] == sourceRequestId) {
            pendingApprovalRequestIdOf[proposalId][voter] = bytes32(0);
            if (pendingApprovalCountOf[proposalId] != 0) {
                unchecked {
                    pendingApprovalCountOf[proposalId] -= 1;
                }
            }
        }
        recordedVoteReceiptOf[proposalId][voter] = recordedVote;
        emit ApprovalRecorded(proposalId, voter, sourceRequestId, recordedVote);
    }

    function onProposalFinalized(bytes memory data) external onlyInbox {
        (uint256 proposalId, bool approved, ctUint64 yesVotes, ctUint64 noVotes) =
            abi.decode(data, (uint256, bool, ctUint64, ctUint64));
        bytes32 sourceRequestId = _currentSourceRequestId();
        if (pendingFinalizeRequestIdOf[proposalId] == sourceRequestId) {
            pendingFinalizeRequestIdOf[proposalId] = bytes32(0);
        }

        PayoutProposal storage proposal = proposals[proposalId];
        proposal.finalized = true;
        proposal.approved = approved;
        encryptedYesVotesOf[proposalId] = yesVotes;
        encryptedNoVotesOf[proposalId] = noVotes;

        emit ProposalFinalized(proposalId, sourceRequestId, approved, yesVotes, noVotes);
    }

    function onProposalRegisterError(bytes memory data) external onlyInbox {
        (uint256 proposalId, bytes memory reason) = abi.decode(data, (uint256, bytes));
        bytes32 sourceRequestId = _currentSourceRequestId();
        if (pendingRegisterRequestIdOf[proposalId] == sourceRequestId) {
            pendingRegisterRequestIdOf[proposalId] = bytes32(0);
        }
        emit ProposalRegistrationFailed(proposalId, sourceRequestId, reason);
    }

    function onApprovalError(bytes memory data) external onlyInbox {
        (uint256 proposalId, address voter, bytes memory reason) = abi.decode(data, (uint256, address, bytes));
        bytes32 sourceRequestId = _currentSourceRequestId();
        if (voter != address(0) && pendingApprovalRequestIdOf[proposalId][voter] == sourceRequestId) {
            pendingApprovalRequestIdOf[proposalId][voter] = bytes32(0);
            if (pendingApprovalCountOf[proposalId] != 0) {
                unchecked {
                    pendingApprovalCountOf[proposalId] -= 1;
                }
            }
        }
        emit ApprovalFailed(proposalId, voter, sourceRequestId, reason);
    }

    function onFinalizeError(bytes memory data) external onlyInbox {
        (uint256 proposalId, bytes memory reason) = abi.decode(data, (uint256, bytes));
        bytes32 sourceRequestId = _currentSourceRequestId();
        if (pendingFinalizeRequestIdOf[proposalId] == sourceRequestId) {
            pendingFinalizeRequestIdOf[proposalId] = bytes32(0);
        }
        emit FinalizeFailed(proposalId, sourceRequestId, reason);
    }

    function _registerProposalRemote(uint256 proposalId, uint256 callbackFeeLocalWei, uint256 totalValueWei)
        internal
        returns (bytes32 requestId)
    {
        PayoutProposal storage proposal = _requireExistingProposal(proposalId);
        if (proposal.registered) revert ProposalAlreadyRegistered(proposalId);
        bytes32 pendingRegister = pendingRegisterRequestIdOf[proposalId];
        if (pendingRegister != bytes32(0)) revert ProposalRegisterPending(proposalId, pendingRegister);

        IInbox.MpcMethodCall memory methodCall =
            MpcAbiCodec.create(IPrivateTreasuryApprovalCoti.registerProposal.selector, 3)
                .addArgument(proposalId)
                .addArgument(uint256(proposal.threshold))
                .addArgument(uint256(proposal.deadline))
                .build();

        requestId = _sendTwoWayWithFee(
            totalValueWei,
            callbackFeeLocalWei,
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            PrivateTreasuryApproval.onProposalRegistered.selector,
            PrivateTreasuryApproval.onProposalRegisterError.selector
        );

        pendingRegisterRequestIdOf[proposalId] = requestId;
        emit ProposalRegistrationRequested(proposalId, requestId);
    }

    function _requireExistingProposal(uint256 proposalId) internal view returns (PayoutProposal storage proposal) {
        proposal = proposals[proposalId];
        if (!proposal.exists) revert ProposalUnknown(proposalId);
    }

    function _requireActiveProposal(uint256 proposalId) internal view returns (PayoutProposal storage proposal) {
        proposal = _requireExistingProposal(proposalId);
        if (!proposal.registered) revert ProposalNotRegistered(proposalId);
        if (proposal.finalized) revert ProposalAlreadyFinalized(proposalId);
    }

    function _currentSourceRequestId() private view returns (bytes32 requestId) {
        requestId = inbox.inboxSourceRequestId();
        if (requestId == bytes32(0)) {
            requestId = inbox.inboxRequestId();
        }
    }
}
