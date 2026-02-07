// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./IInboxMiner.sol";
import "./InboxBase.sol";
import "./MinerBase.sol";

contract InboxMiner is InboxBase, MinerBase, IInboxMiner {
    /// @notice Create an Inbox miner with the given chain ID.
    /// @param _chainId The chain ID this inbox serves.
    constructor(uint256 _chainId) InboxBase(_chainId) MinerBase(msg.sender) {}

    /// @notice Executes a mined incoming request on the target chain
    /// @dev Builds calldata from the request (raw calldata or MPC re-encode), sets execution context,
    ///      calls target, clears context, marks executed, and records errors.
    /// @param incomingRequest The incoming request to execute
    /// @param sourceChainId The chain ID that sent the request
    function _executeIncomingRequest(
        Request storage incomingRequest,
        uint sourceChainId
    ) internal {
        // Set execution context
        _currentContext = ExecutionContext({
            remoteChainId: sourceChainId,
            remoteContract: incomingRequest.originalSender,
            requestId: incomingRequest.requestId
        });

        // Deliver message to target contract
        address targetContract = incomingRequest.targetContract;
        bytes memory callData = _encodeMethodCall(incomingRequest.methodCall);

        (bool success, bytes memory returnData) = targetContract.call(callData);

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
                requestId: incomingRequest.requestId,
                errorCode: 1,
                errorMessage: returnData
            });
            errors[incomingRequest.requestId] = err;
            emit ErrorReceived(incomingRequest.requestId, 1, returnData);
        }
        // If success and respond() was called, the response request was already created
    }

    /// @notice Processes mined requests and errors from a source chain
    /// @dev Handles response requests by triggering callbacks and processes errors by triggering error handlers.
    ///      Response data is stored from the executed request's encoded calldata.
    /// @param sourceChainId The chain ID that the requests/errors came from
    /// @param mined Array of mined requests (responses) to process
    /// @param minedErrors Array of mined errors to process
    function batchProcessRequests(
        uint sourceChainId,
        MinedRequest[] memory mined,
        MinedError[] memory minedErrors
    ) external onlyMiner {
        require(sourceChainId != chainId, "Inbox: sourceChainId cannot be this chain");

        // Process incoming requests (including response requests)
        for (uint i = 0; i < mined.length; i++) {
            MinedRequest memory minedRequest = mined[i];
            bytes32 requestId = minedRequest.requestId;
            Request storage incomingRequest = incomingRequests[requestId];

            if (incomingRequest.requestId == bytes32(0)) {
                require(minedRequest.sourceContract != address(0), "Inbox: invalid source contract");
                require(minedRequest.targetContract != address(0), "Inbox: invalid target contract");

                Request memory newIncomingRequest = Request({
                    requestId: requestId,
                    targetChainId: sourceChainId,
                    targetContract: minedRequest.targetContract,
                    methodCall: minedRequest.methodCall,
                    callerContract: minedRequest.sourceContract,
                    originalSender: minedRequest.sourceContract,
                    timestamp: uint64(block.timestamp),
                    callbackSelector: minedRequest.callbackSelector,
                    errorSelector: minedRequest.errorSelector,
                    isTwoWay: minedRequest.isTwoWay,
                    executed: false,
                    sourceRequestId: minedRequest.sourceRequestId
                });

                incomingRequests[requestId] = newIncomingRequest;
                incomingRequest = incomingRequests[requestId];

                emit MessageReceived(requestId, sourceChainId, minedRequest.sourceContract, minedRequest.methodCall);
            }

            if (!incomingRequest.executed) {
                _executeIncomingRequest(incomingRequest, sourceChainId);
            }

            // If this is a response request (one-way with sourceRequestId set),
            // update the original request as executed and store the response data.
            if (incomingRequest.requestId != bytes32(0) &&
                incomingRequest.sourceRequestId != bytes32(0) &&
                !incomingRequest.isTwoWay) {
                bytes32 originalRequestId = incomingRequest.sourceRequestId;
                Request storage originalRequest = requests[originalRequestId];

                if (originalRequest.requestId != bytes32(0) && !originalRequest.executed) {
                    Response memory response = Response({
                        responseRequestId: originalRequestId,
                        response: _encodeMethodCall(incomingRequest.methodCall)
                    });

                    inboxResponses[originalRequestId] = response;
                    originalRequest.executed = true;

                    emit ResponseReceived(originalRequestId, _encodeMethodCall(incomingRequest.methodCall));
                }
            }
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
