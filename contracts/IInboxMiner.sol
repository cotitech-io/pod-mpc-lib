// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "./IInbox.sol";

interface IInboxMiner {
    struct MinedRequest {
        bytes32 requestId;
        address sourceContract;
        address targetContract;
        bytes data;
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

    function batchProcessRequests(
        uint sourceChainId, MinedRequest[] memory mined, MinedError[] memory minedErrors
    ) external;
}