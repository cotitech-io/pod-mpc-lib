// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../../IInbox.sol";
import "../../mpc/PodLibBase.sol";
import "../../mpccodec/MpcAbiCodec.sol";
import "./IPrivateBudgetGuardCoti.sol";

/// @title PrivateBudgetGuard
/// @notice Source-chain PoD example that registers a remote private budget and evaluates private spend attempts.
contract PrivateBudgetGuard is PodLibBase, ReentrancyGuard {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    error BudgetNotReady(address owner);
    error BudgetRegistrationPending(address owner, bytes32 requestId);
    error SpendAlreadyPending(address owner, bytes32 requestId);

    event PendingCleared(
        address indexed owner, bytes32 previousRegisterRequestId, bytes32 previousSpendRequestId
    );
    event BudgetRegistrationRequested(address indexed owner, bytes32 indexed requestId);
    event BudgetRegistered(address indexed owner, bytes32 indexed requestId, ctUint64 remainingBudget);
    event BudgetRegistrationFailed(address indexed owner, bytes32 indexed requestId, bytes reason);
    event SpendRequested(address indexed owner, bytes32 indexed requestId);
    event SpendEvaluated(
        address indexed owner, bytes32 indexed requestId, ctBool approved, ctUint64 remainingBudget
    );
    event SpendFailed(address indexed owner, bytes32 indexed requestId, bytes reason);

    mapping(address => bool) public budgetInitialized;
    mapping(address => ctUint64) public remainingBudgetOf;
    mapping(address => ctBool) public lastApprovalOf;
    mapping(address => bytes32) public pendingRegisterRequestIdOf;
    mapping(address => bytes32) public pendingSpendRequestIdOf;

    constructor(address _inbox) PodLibBase(msg.sender) {
        setInbox(_inbox);
    }

    /// @notice Register or replace the caller's private budget on the COTI-side contract.
    function registerBudget(itUint64 calldata budget, uint256 callbackFeeLocalWei)
        external
        payable
        nonReentrant
        returns (bytes32 requestId)
    {
        bytes32 pendingRegister = pendingRegisterRequestIdOf[msg.sender];
        if (pendingRegister != bytes32(0)) {
            revert BudgetRegistrationPending(msg.sender, pendingRegister);
        }
        bytes32 pendingSpend = pendingSpendRequestIdOf[msg.sender];
        if (pendingSpend != bytes32(0)) {
            revert SpendAlreadyPending(msg.sender, pendingSpend);
        }

        IInbox.MpcMethodCall memory methodCall = MpcAbiCodec.create(IPrivateBudgetGuardCoti.registerBudget.selector, 2)
            .addArgument(msg.sender)
            .addArgument(budget)
            .build();

        requestId = _sendTwoWayWithFee(
            msg.value,
            callbackFeeLocalWei,
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            PrivateBudgetGuard.onBudgetRegistered.selector,
            PrivateBudgetGuard.onRegisterBudgetError.selector
        );

        pendingRegisterRequestIdOf[msg.sender] = requestId;
        emit BudgetRegistrationRequested(msg.sender, requestId);
    }

    /// @notice Submit a private spend attempt against the caller's remotely stored budget.
    function submitSpend(itUint64 calldata amount, uint256 callbackFeeLocalWei)
        external
        payable
        nonReentrant
        returns (bytes32 requestId)
    {
        bytes32 pendingRegister = pendingRegisterRequestIdOf[msg.sender];
        if (pendingRegister != bytes32(0)) {
            revert BudgetRegistrationPending(msg.sender, pendingRegister);
        }
        if (!budgetInitialized[msg.sender]) {
            revert BudgetNotReady(msg.sender);
        }
        bytes32 pendingSpend = pendingSpendRequestIdOf[msg.sender];
        if (pendingSpend != bytes32(0)) {
            revert SpendAlreadyPending(msg.sender, pendingSpend);
        }

        IInbox.MpcMethodCall memory methodCall = MpcAbiCodec.create(IPrivateBudgetGuardCoti.checkAndSpend.selector, 2)
            .addArgument(msg.sender)
            .addArgument(amount)
            .build();

        requestId = _sendTwoWayWithFee(
            msg.value,
            callbackFeeLocalWei,
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            PrivateBudgetGuard.onSpendEvaluated.selector,
            PrivateBudgetGuard.onSpendError.selector
        );

        pendingSpendRequestIdOf[msg.sender] = requestId;
        emit SpendRequested(msg.sender, requestId);
    }

    /// @notice Owner-only escape hatch for users stuck behind a missing callback.
    function clearPending(address owner) external onlyOwner {
        bytes32 previousRegisterRequestId = pendingRegisterRequestIdOf[owner];
        bytes32 previousSpendRequestId = pendingSpendRequestIdOf[owner];
        pendingRegisterRequestIdOf[owner] = bytes32(0);
        pendingSpendRequestIdOf[owner] = bytes32(0);
        emit PendingCleared(owner, previousRegisterRequestId, previousSpendRequestId);
    }

    /// @notice Inbox callback after successful remote budget registration.
    function onBudgetRegistered(bytes memory data) external onlyInbox {
        (address owner, ctUint64 remainingBudget) = abi.decode(data, (address, ctUint64));
        bytes32 sourceRequestId = _currentSourceRequestId();
        if (owner != address(0) && pendingRegisterRequestIdOf[owner] == sourceRequestId) {
            pendingRegisterRequestIdOf[owner] = bytes32(0);
        }
        budgetInitialized[owner] = true;
        remainingBudgetOf[owner] = remainingBudget;
        emit BudgetRegistered(owner, sourceRequestId, remainingBudget);
    }

    /// @notice Inbox callback after remote spend evaluation.
    function onSpendEvaluated(bytes memory data) external onlyInbox {
        (address owner, ctBool approved, ctUint64 remainingBudget) = abi.decode(data, (address, ctBool, ctUint64));
        bytes32 sourceRequestId = _currentSourceRequestId();
        if (owner != address(0) && pendingSpendRequestIdOf[owner] == sourceRequestId) {
            pendingSpendRequestIdOf[owner] = bytes32(0);
        }
        lastApprovalOf[owner] = approved;
        remainingBudgetOf[owner] = remainingBudget;
        emit SpendEvaluated(owner, sourceRequestId, approved, remainingBudget);
    }

    /// @notice Inbox error callback for remote budget registration failures.
    function onRegisterBudgetError(bytes memory data) external onlyInbox {
        (address owner, bytes memory reason) = abi.decode(data, (address, bytes));
        bytes32 sourceRequestId = _currentSourceRequestId();
        if (owner != address(0) && pendingRegisterRequestIdOf[owner] == sourceRequestId) {
            pendingRegisterRequestIdOf[owner] = bytes32(0);
        }
        emit BudgetRegistrationFailed(owner, sourceRequestId, reason);
    }

    /// @notice Inbox error callback for remote spend evaluation failures.
    function onSpendError(bytes memory data) external onlyInbox {
        (address owner, bytes memory reason) = abi.decode(data, (address, bytes));
        bytes32 sourceRequestId = _currentSourceRequestId();
        if (owner != address(0) && pendingSpendRequestIdOf[owner] == sourceRequestId) {
            pendingSpendRequestIdOf[owner] = bytes32(0);
        }
        emit SpendFailed(owner, sourceRequestId, reason);
    }

    function _currentSourceRequestId() private view returns (bytes32 requestId) {
        requestId = inbox.inboxSourceRequestId();
        if (requestId == bytes32(0)) {
            requestId = inbox.inboxRequestId();
        }
    }
}
