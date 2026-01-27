// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "./IInbox.sol";

interface IInboxMiner {
    struct MinedRequest {
        bytes32 requestId;
        address sourceContract;
        address targetContract;
        IInbox.MpcMethodCall methodCall;
        bytes4 callbackSelector;
        bytes4 errorSelector;
        bool isTwoWay;
        bytes32 sourceRequestId;
    }

    struct MinedError {
        bytes32 requestId;
        uint64 errorCode;
        bytes errorMessage;
    }

    /// @notice Process mined requests and errors for a source chain.
    /// @param sourceChainId The source chain ID that produced the mined data.
    /// @param mined The mined requests to process.
    /// @param minedErrors The mined errors to process.
    function batchProcessRequests(
        uint sourceChainId, MinedRequest[] memory mined, MinedError[] memory minedErrors
    ) external;
}