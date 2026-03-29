// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IInboxMiner.sol";
import "./InboxBase.sol";
import "./MinerBase.sol";

contract InboxMiner is InboxBase, MinerBase, IInboxMiner {
    /// @notice Create an Inbox miner with the given chain ID.
    /// @param _chainId The chain ID this inbox serves.
    constructor(uint256 _chainId) InboxBase(_chainId) MinerBase(msg.sender) {}

    /// @notice Executes a mined incoming request on the target chain
    /// @dev Builds calldata from the request (raw calldata or MPC re-encode), sets execution context,
    ///      then calls the target with `gas` capped by `incomingRequest.targetFee` (**gas units**, not wei).
    ///      Does not use `tx.gasprice` for execution budgeting—`targetFee` is already a gas budget.
    /// @param incomingRequest The incoming request to execute
    /// @param sourceChainId The chain ID that sent the request
    function _executeIncomingRequest(Request storage incomingRequest, uint sourceChainId) internal {
        // Set execution context
        _currentContext = ExecutionContext({
            remoteChainId: sourceChainId,
            remoteContract: incomingRequest.originalSender,
            requestId: incomingRequest.requestId
        });

        address targetContract = incomingRequest.targetContract;
        (bool encodedOk, bytes memory callData, bytes memory encodeErr) = _safeEncodeMethodCall(
            incomingRequest.methodCall
        );

        if (!encodedOk) {
            _recordEncodeError(incomingRequest.requestId, encodeErr);

            // Always clear execution context after execution
            _currentContext = ExecutionContext({
                remoteChainId: 0,
                remoteContract: address(0),
                requestId: bytes32(0)
            });

            // Mark as executed after delivery
            incomingRequest.executed = true;
            return;
        }

        uint256 targetGasBudget = incomingRequest.targetFee;
        uint256 gasBeforeSubcall = gasleft();

        bool success;
        bytes memory returnData;
        (success, returnData) = targetContract.call{gas: targetGasBudget}(callData);

        uint256 gasUsed = gasBeforeSubcall - gasleft();
        uint256 gasRemainingApprox = targetGasBudget > gasUsed ? targetGasBudget - gasUsed : 0;
        emit FeeExecutionSettled(incomingRequest.requestId, gasUsed, gasRemainingApprox);

        _currentContext = ExecutionContext({
            remoteChainId: 0,
            remoteContract: address(0),
            requestId: bytes32(0)
        });

        incomingRequest.executed = true;

        if (!success) {
            bytes32 rid = incomingRequest.requestId;
            errors[rid] = Error({
                requestId: rid,
                errorCode: ERROR_CODE_EXECUTION_FAILED,
                errorMessage: returnData
            });
            emit ErrorReceived(rid, ERROR_CODE_EXECUTION_FAILED, returnData);
        }
    }

    /// @notice Processes mined requests and errors from a source chain
    /// @dev Handles response requests by triggering callbacks and processes errors by triggering error handlers.
    ///      Response data is stored from the executed request's encoded calldata.
    /// @param sourceChainId The chain ID that the requests/errors came from
    /// @param mined Array of mined requests (responses) to process
    function batchProcessRequests(uint sourceChainId, MinedRequest[] memory mined) external onlyMiner {
        require(sourceChainId != chainId, "Inbox: sourceChainId cannot be this chain");

        uint256 allowedNonce = 1;
        if (lastIncomingRequestId[sourceChainId] != bytes32(0)) {
            (, allowedNonce) = _unpackRequestId(lastIncomingRequestId[sourceChainId]);
            allowedNonce++;
        }

        // Process incoming requests (including response requests)
        // Process incoming requests (including response requests)
        for (uint i = 0; i < mined.length; i++) {
            MinedRequest memory minedRequest = mined[i];
            bytes32 requestId = minedRequest.requestId;
            (, uint256 minedNonce) = _unpackRequestId(requestId);
            require(minedNonce == allowedNonce, "Inbox: mined nonces must be contiguous");
            allowedNonce++;
            Request storage incomingRequest = incomingRequests[requestId];
            require(incomingRequest.requestId == bytes32(0), "Inbox: request already processed");
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
                sourceRequestId: minedRequest.sourceRequestId,
                targetFee: minedRequest.targetFee,
                callerFee: minedRequest.callerFee
            });

            incomingRequests[requestId] = newIncomingRequest;
            incomingRequest = incomingRequests[requestId];
            emit MessageReceived(requestId, sourceChainId, minedRequest.sourceContract, minedRequest.methodCall);

            _executeIncomingRequest(incomingRequest, sourceChainId);

            // If this is a response request (one-way with sourceRequestId set),
            // update the original request as executed and store the response data.
            if (incomingRequest.requestId != bytes32(0) && incomingRequest.sourceRequestId != bytes32(0)
                && !incomingRequest.isTwoWay) {
                bytes32 originalRequestId = incomingRequest.sourceRequestId;
                Request storage originalRequest = requests[originalRequestId];

                if (originalRequest.requestId != bytes32(0) && !originalRequest.executed) {
                    originalRequest.executed = true;
                    emit IncomingResponseReceived(originalRequestId, incomingRequest.requestId);
                }
            }
        }

        if (mined.length > 0) {
            lastIncomingRequestId[sourceChainId] = mined[mined.length - 1].requestId;
        }
    }

    /// @notice Sets the price oracle used for cross-chain fee conversion.
    function setPriceOracle(address oracle) external onlyOwner {
        _setPriceOracle(oracle);
    }

    /// @notice Updates minimum fee templates for local (callback) and remote execution legs.
    function updateMinFeeConfigs(FeeConfig memory _local, FeeConfig memory _remote) external onlyOwner {
        _updateMinFeeConfigs(_local, _remote);
    }

    /// @notice Withdraws the full native balance (accumulated message fees) to the owner.
    /// @dev Safe to call when balance is zero. Unspent wei from `sendTwoWayMessage` / `sendOneWayMessage` remains here until collected.
    function collectFees() external onlyOwner {
        uint256 amount = address(this).balance;
        if (amount == 0) {
            return;
        }
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "Inbox: fee transfer failed");
    }
}
