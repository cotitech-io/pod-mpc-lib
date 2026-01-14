// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IInboxMiner.sol";
import "./IInbox.sol";
import "./InboxBase.sol";

contract InboxMiner is InboxBase, IInboxMiner {
    // Pending requests organized by source chain ID
    // For outgoing requests: sourceChainId is this chain's ID
    // For incoming requests: sourceChainId is the chain they came from
    mapping(uint256 => Request[]) public pendingRequestsByChain;
    
    constructor(uint256 _chainId) InboxBase(_chainId) {}

    /// @notice Processes mined requests and errors from a source chain
    /// @dev Handles response requests by triggering callbacks and processes errors by triggering error handlers
    /// @param sourceChainId The chain ID that the requests/errors came from
    /// @param mined Array of mined requests (responses) to process
    /// @param minedErrors Array of mined errors to process
    function batchProcessRequests(
        uint sourceChainId,
        MinedRequest[] memory mined,
        MinedError[] memory minedErrors
    ) external {
        require(sourceChainId != chainId, "Inbox: sourceChainId cannot be this chain");
        
        // Process incoming requests (including response requests)
        for (uint i = 0; i < mined.length; i++) {
            bytes32 requestId = mined[i].requestId;
            Request storage incomingRequest = incomingRequests[requestId];
            
            // Check if this is a response request (one-way with sourceRequestId set)
            if (incomingRequest.requestId != bytes32(0) && 
                incomingRequest.sourceRequestId != bytes32(0) &&
                !incomingRequest.isTwoWay) {
                // This is a response request - decode and trigger callback
                bytes32 originalRequestId = incomingRequest.sourceRequestId;
                Request storage originalRequest = requests[originalRequestId];
                
                if (originalRequest.requestId != bytes32(0) && 
                    !originalRequest.executed &&
                    originalRequest.isTwoWay) {
                    // Mark as executed when response is processed
                    originalRequest.executed = true;
                    
                    // Decode response data (data, sourceRequestId)
                    (bytes memory responseData, ) = abi.decode(mined[i].response, (bytes, bytes32));
                    
                    Response memory response = Response({
                        requestId: originalRequestId,
                        response: responseData
                    });
                    
                    responses[originalRequestId] = response;
                    
                    emit ResponseReceived(originalRequestId, responseData);
                    
                    // Call the callback function on the original sender contract
                    // Wrap in ExecutionContext so consuming contract can use inboxMsgSender()
                    if (originalRequest.callbackSelector != bytes4(0)) {
                        address originalSender = originalRequest.originalSender;
                        if (originalSender != address(0)) {
                            // Set up execution context
                            ExecutionContext memory prevContext = _currentContext;
                            
                            _currentContext = ExecutionContext({
                                remoteChainId: sourceChainId,
                                remoteContract: originalRequest.targetContract,
                                requestId: originalRequestId
                            });
                            
                            // Execute callback
                            (bool success, ) = originalSender.call(
                                abi.encodeWithSelector(originalRequest.callbackSelector, originalRequestId)
                            );
                            
                            // Clear execution context
                            _currentContext = prevContext;
                            
                            if (!success) {
                                // Store as error instead
                                Error memory err = Error({
                                    requestId: originalRequestId,
                                    errorCode: 2,
                                    errorMessage: "Callback failed"
                                });
                                errors[originalRequestId] = err;
                                emit ErrorReceived(originalRequestId, 2, "Callback failed");
                            }
                        }
                    }
                }
            }
            // Otherwise, this is a regular incoming request that needs to be delivered
            // (handled by deliverMessage)
        }
        
        // Process errors for outgoing requests (both two-way and one-way)
        for (uint i = 0; i < minedErrors.length; i++) {
            bytes32 requestId = minedErrors[i].requestId;
            Request storage request = requests[requestId];
            
            // Verify the request is for the correct target chain
            // Mark as executed when error is processed
            if (request.requestId != bytes32(0) && 
                request.targetChainId == sourceChainId &&
                !request.executed) {
                request.executed = true;
                
                Error memory err = Error({
                    requestId: requestId,
                    errorCode: minedErrors[i].errorCode,
                    errorMessage: minedErrors[i].errorMessage
                });
                
                errors[requestId] = err;
                
                emit ErrorReceived(requestId, minedErrors[i].errorCode, minedErrors[i].errorMessage);
                
                // Call the error handler on the original sender (for both two-way and one-way)
                // Wrap in ExecutionContext so consuming contract can use inboxMsgSender()
                if (request.errorSelector != bytes4(0)) {
                    address originalSender = request.originalSender;
                    if (originalSender != address(0)) {
                        // Set up execution context
                        ExecutionContext memory prevContext = _currentContext;
                        
                        _currentContext = ExecutionContext({
                            remoteChainId: sourceChainId,
                            remoteContract: request.targetContract,
                            requestId: requestId
                        });
                        
                        // Execute error handler
                        (bool success, ) = originalSender.call(
                            abi.encodeWithSelector(request.errorSelector, requestId)
                        );
                        
                        // Restore previous context (or clear if there was none)
                        _currentContext = prevContext;
                        
                        if (!success) {
                            // Error handler failed, but we've already stored the error
                        }
                    }
                }
            }
        }
    }
    
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

    /// @notice Gets pending requests for a specific source chain
    /// @param sourceChainId The source chain ID to get pending requests for
    /// @param from The starting index (0-based)
    /// @param length The number of requests to return
    /// @return Array of pending requests
    function getPendingRequests(
        uint sourceChainId,
        uint from,
        uint length
    ) external view returns (Request[] memory) {
        Request[] storage chainRequests = pendingRequestsByChain[sourceChainId];
        uint totalPending = chainRequests.length;
        
        if (from >= totalPending) {
            return new Request[](0);
        }
        
        uint end = from + length;
        if (end > totalPending) {
            end = totalPending;
        }
        
        uint resultLength = end - from;
        Request[] memory result = new Request[](resultLength);
        
        for (uint i = 0; i < resultLength; i++) {
            result[i] = chainRequests[from + i];
        }
        
        return result;
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
        pendingRequestsByChain[sourceChainId].push(incomingRequest);
        _requestSourceContracts[requestId] = sourceContract; // Store source contract
        
        emit MessageReceived(requestId, sourceChainId, sourceContract, data);
    }
    
    /// @notice Sends a two-way message and adds it to pending requests for miners
    /// @dev Overrides base implementation to track pending requests
    /// @param targetChainId The chain ID of the target chain
    /// @param targetContract The address of the target contract on the target chain
    /// @param data The encoded function call data to send
    /// @param callbackSelector The function selector to call when response is received
    /// @param errorSelector The function selector to call when an error occurs
    /// @return requestId The unique request ID for this message
    function sendTwoWayMessage(
        uint256 targetChainId,
        address targetContract,
        bytes memory data,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) external override returns (bytes32) {
        bytes32 requestId = _sendTwoWayMessage(
            targetChainId,
            targetContract,
            data,
            callbackSelector,
            errorSelector
        );
        
        // Add to pending requests for miners, organized by target chain
        // For outgoing requests, the sourceChainId for miners is this chain's ID
        pendingRequestsByChain[chainId].push(requests[requestId]);
        
        return requestId;
    }
    
    /// @notice Sends a one-way message and adds it to pending requests for miners
    /// @dev Overrides base implementation to track pending requests
    /// @param targetChainId The chain ID of the target chain
    /// @param targetContract The address of the target contract on the target chain
    /// @param data The encoded function call data to send
    /// @param errorSelector The function selector to call when an error occurs
    /// @return requestId The unique request ID for this message
    function sendOneWayMessage(
        uint256 targetChainId,
        address targetContract,
        bytes memory data,
        bytes4 errorSelector
    ) external override returns (bytes32) {
        bytes32 requestId = _sendOneWayMessage(targetChainId, targetContract, data, errorSelector, bytes32(0));
        
        // Add to pending requests for miners, organized by target chain
        pendingRequestsByChain[chainId].push(requests[requestId]);
        
        return requestId;
    }
}
