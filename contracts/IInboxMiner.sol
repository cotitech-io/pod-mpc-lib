// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "./IInbox.sol";

interface IInboxMiner {
    struct MinedRequest {
        bytes32 requestId;
        bytes response;
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