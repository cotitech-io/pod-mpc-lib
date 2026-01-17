// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IInboxMiner.sol";
import "./InboxBase.sol";

contract InboxMiner is InboxBase, IInboxMiner {
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

                            // Restore execution context
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

                        // Restore execution context
                        _currentContext = prevContext;

                        if (!success) {
                            // Error handler failed, but we've already stored the error
                        }
                    }
                }
            }
        }
    }
}
