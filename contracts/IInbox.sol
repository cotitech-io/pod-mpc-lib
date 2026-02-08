// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IInbox {
    struct MpcMethodCall {
        bytes4 selector;
        bytes data;
        bytes8[] datatypes;
        bytes32[] datalens;
    }

    struct Request {
        bytes32 requestId;
        uint256 targetChainId;
        address targetContract;
        MpcMethodCall methodCall;
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
        bytes32 responseRequestId;
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

    /// @notice Send a two-way message to a target chain with callback and error handlers.
    /// @param targetChainId The target chain ID.
    /// @param targetContract The target contract address on the target chain.
    /// @param methodCall The method call metadata and arguments.
    /// @param callbackSelector Selector to invoke on response.
    /// @param errorSelector Selector to invoke on error.
    /// @return requestId The created request ID.
    function sendTwoWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall calldata methodCall,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) external returns (bytes32);

    /// @notice Send a one-way message to a target chain with an error handler.
    /// @param targetChainId The target chain ID.
    /// @param targetContract The target contract address on the target chain.
    /// @param methodCall The method call metadata and arguments.
    /// @param errorSelector Selector to invoke on error.
    /// @return requestId The created request ID.
    function sendOneWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall calldata methodCall,
        bytes4 errorSelector
    ) external returns (bytes32);

    /// @notice Get error information for a failed outgoing request.
    /// @param requestId The request ID to query.
    /// @return code The error code.
    /// @return message The error message.
    function getOutboxError(bytes32 requestId) external view returns (uint256 code, string memory message);

    /// @notice Get response data for an incoming request.
    /// @param requestId The request ID to query.
    /// @return response The response data bytes.
    function getInboxResponse(bytes32 requestId) external view returns (bytes memory);

    /// @notice Get the sender info for the currently executing message.
    /// @return chainId The remote chain ID.
    /// @return contractAddress The remote contract address.
    function inboxMsgSender() external view returns (uint256 chainId, address contractAddress);

    /// @notice Respond to the current incoming message.
    /// @param data The response payload to send back.
    function respond(bytes memory data) external;

    /// @notice Pack chain ID and nonce into a request ID.
    /// @param chainId The chain ID.
    /// @param nonce The request nonce.
    /// @return requestId The packed request ID.
    function getRequestId(uint chainId, uint nonce) external pure returns (bytes32);

    /// @notice Unpack a request ID into chain ID and nonce.
    /// @param requestId The packed request ID.
    /// @return chainId The unpacked chain ID.
    /// @return nonce The unpacked nonce.
    function unpackRequestId(bytes32 requestId) external pure returns (uint chainId, uint nonce);

    /// @notice Get a range of requests in nonce order.
    /// @param from The starting index (0-based).
    /// @param len The number of requests to return.
    /// @return requestsList The list of requests.
    function getRequests(uint from, uint len) external view returns (Request[] memory);

    /// @notice Get the total number of requests.
    /// @return count The total request count.
    function getRequestsLen() external view returns (uint);
}