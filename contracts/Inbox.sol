// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./InboxMiner.sol";

contract Inbox is InboxMiner {

    constructor(uint256 _chainId) InboxMiner(_chainId) {}

    /// @notice Delivers an incoming message to its target contract
    /// @dev Called by miners/relayers after registering the incoming request. Sets execution context during delivery.
    /// @param requestId The request ID of the incoming message
    /// @param sourceChainId The chain ID that sent the message
    /// @param sourceContract The contract address that sent the message
    function deliverMessage(
        bytes32 requestId,
        uint256 sourceChainId,
        address sourceContract
    ) external {
        Request storage incomingRequest = incomingRequests[requestId];
        require(incomingRequest.requestId != bytes32(0), "Inbox: request not found");
        require(!incomingRequest.executed, "Inbox: already executed");
        require(sourceChainId != chainId, "Inbox: cannot receive from same chain");

        // Set execution context
        _currentContext = ExecutionContext({
            remoteChainId: sourceChainId,
            remoteContract: sourceContract,
            requestId: requestId
        });

        // Deliver message to target contract
        address targetContract = incomingRequest.targetContract;
        bytes memory data = incomingRequest.data;

        (bool success, bytes memory returnData) = targetContract.call(data);

        // Always clear execution context after execution
        _currentContext = ExecutionContext({
            remoteChainId: 0,
            remoteContract: address(0),
            requestId: bytes32(0)
        });

        // Mark as executed after delivery
        incomingRequest.executed = true;

        if (!success) {
            // Handle error
            Error memory err = Error({
                requestId: requestId,
                errorCode: 1,
                errorMessage: returnData
            });
            errors[requestId] = err;
            emit ErrorReceived(requestId, 1, returnData);
        }
        // If success and respond() was called, the response request was already created
    }

    /// @notice Registers an incoming request from another chain
    /// @dev Called by miners/relayers when a request is mined on this chain
    /// @param requestId The request ID of the incoming message
    /// @param sourceChainId The chain ID that sent the message
    /// @param sourceContract The contract address that sent the message
    /// @param targetContract The target contract address on this chain
    /// @param data The encoded function call data
    /// @param isTwoWay Whether this is a two-way message
    /// @param sourceRequestId The original request ID if this is a response request
    function registerIncomingRequest(
        bytes32 requestId,
        uint256 sourceChainId,
        address sourceContract,
        address targetContract,
        bytes memory data,
        bool isTwoWay,
        bytes32 sourceRequestId
    ) external {
        require(sourceChainId != chainId, "Inbox: cannot receive from same chain");
        require(incomingRequests[requestId].requestId == bytes32(0), "Inbox: request already exists");

        Request memory incomingRequest = Request({
            requestId: requestId,
            targetChainId: sourceChainId, // Source chain ID
            targetContract: targetContract,
            data: data,
            callerContract: sourceContract, // The contract that sent the message
            originalSender: sourceContract, // Original sender on source chain
            timestamp: uint64(block.timestamp),
            callbackSelector: bytes4(0), // Not used for incoming
            errorSelector: bytes4(0), // Not used for incoming
            isTwoWay: isTwoWay,
            executed: false,
            sourceRequestId: sourceRequestId // Set if this is a response request
        });

        incomingRequests[requestId] = incomingRequest;
        _requestSourceContracts[requestId] = sourceContract; // Store source contract

        emit MessageReceived(requestId, sourceChainId, sourceContract, data);
    }

}
