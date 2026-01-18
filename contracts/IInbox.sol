// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IInbox {
    struct Request {
        bytes32 requestId;
        uint256 targetChainId;
        address targetContract;
        bytes data;
        address callerContract;
        address originalSender;
        uint64 timestamp;
        bytes4 callbackSelector;
        bytes4 errorSelector;
        bool isTwoWay;
        bool executed;
        bytes32 sourceRequestId; // This is in case this request is actually a response to another request
    }

    struct Response {
        bytes32 requestId;
        bytes response;
    }

    struct Error {
        bytes32 requestId;
        uint64 errorCode;
        bytes errorMessage;
    }

    struct ExecutionContext {
        uint256 remoteChainId;
        address remoteContract;
        bytes32 requestId;
    }

    function sendTwoWayMessage(
        uint256 targetChainId,
        address targetContract,
        bytes memory data,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) external returns (bytes32);

    function sendOneWayMessage(
        uint256 targetChainId,
        address targetContract,
        bytes memory data,
        bytes4 errorSelector
    ) external returns (bytes32);

    function getOutboxError(bytes32 requestId) external view returns (uint256 code, string memory message);

    function getInboxResponse(bytes32 requestId) external view returns (bytes memory);

    function inboxMsgSender() external view returns (uint256 chainId, address contractAddress);

    function respond(bytes memory data) external;

    function getRequestId(uint chainId, uint nonce) external pure returns (bytes32);

    function unpackRequestId(bytes32 requestId) external pure returns (uint chainId, uint nonce);

    function getRequests(uint from, uint len) external view returns (Request[] memory);

    function getRequestsLen() external view returns (uint);
}