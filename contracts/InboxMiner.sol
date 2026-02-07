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
    function batchProcessRequests(
        uint sourceChainId,
        MinedRequest[] memory mined
    ) external onlyMiner {
        require(sourceChainId != chainId, "Inbox: sourceChainId cannot be this chain");

        uint256 allowedNonce = 0;
        if (lastIncomingRequestId[sourceChainId] != bytes32(0)) {
            (, allowedNonce) = _unpackRequestId(lastIncomingRequestId[sourceChainId]);
            allowedNonce++;
        }

        // Process incoming requests (including response requests)
        for (uint i = 0; i < mined.length; i++) {
            MinedRequest memory minedRequest = mined[i];
            bytes32 requestId = minedRequest.requestId;
            (, uint256 minedNonce) = _unpackRequestId(requestId);
            require(minedNonce == allowedNonce, "Inbox: mined nonces must be contiguous");
            allowedNonce = minedNonce + 1;
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

        if (mined.length > 0) {
            lastIncomingRequestId[sourceChainId] = mined[mined.length - 1].requestId;
        }

    }

}
