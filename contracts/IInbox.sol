// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @title IInbox
/// @notice Cross-chain request/response inbox: send messages to remote chains, execute incoming calls, and query state.
/// @dev Fee-related fields on {Request} are **gas unit** budgets, not wei. See {InboxFeeManager}.
interface IInbox {
    // --- Types ---

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
        /// @dev If this request is a one-way response or error delivery, links to the original two-way request ID.
        bytes32 sourceRequestId;
        /// @dev Gas unit budget for the remote execution leg (`call{gas: ...}` cap). Not wei.
        uint256 targetFee;
        /// @dev Gas unit budget for the callback leg on the source chain. Not wei.
        uint256 callerFee;
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

    // --- External: sends (payable) ---

    /// @notice Send a two-way message with callback and error handlers on the remote chain.
    /// @param targetChainId Destination chain ID.
    /// @param targetContract Contract to call on the destination chain.
    /// @param methodCall Calldata and MPC metadata.
    /// @param callbackSelector Selector invoked on the source chain when the remote call succeeds.
    /// @param errorSelector Selector invoked on the source chain when the remote call fails.
    /// @param callbackFeeLocalWei Wei from `msg.value` reserved for the callback leg (converted to gas units in fee logic).
    /// @return requestId The new outbound request ID.
    function sendTwoWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall calldata methodCall,
        bytes4 callbackSelector,
        bytes4 errorSelector,
        uint256 callbackFeeLocalWei
    ) external payable returns (bytes32);

    /// @notice Send a one-way message with an error handler only (no callback).
    /// @param targetChainId Destination chain ID.
    /// @param targetContract Contract to call on the destination chain.
    /// @param methodCall Calldata and MPC metadata.
    /// @param errorSelector Selector invoked on error.
    /// @return requestId The new outbound request ID.
    function sendOneWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall calldata methodCall,
        bytes4 errorSelector
    ) external payable returns (bytes32);

    // --- External: execution (non-payable) ---

    /// @notice Respond to the current incoming message (two-way flow).
    /// @param data Payload routed to the original sender via `callbackSelector`.
    function respond(bytes memory data) external;

    /// @notice Signal an application error for the current incoming two-way message (same routing constraints as {respond}).
    /// @param data ABI-encoded argument for the remote `errorSelector(bytes)`.
    function raise(bytes memory data) external;

    // --- External: views ---

    /// @notice Return error details for a failed outgoing request.
    /// @param requestId Outbound request ID.
    /// @return code Error code.
    /// @return message Error message or revert data.
    function getOutboxError(bytes32 requestId) external view returns (uint256 code, string memory message);

    /// @notice Return stored response bytes for a completed incoming flow.
    /// @param requestId Incoming request ID.
    /// @return response Response payload.
    function getInboxResponse(bytes32 requestId) external view returns (bytes memory);

    /// @notice Return a slice of outbound requests in nonce order.
    /// @param from Start index (0-based).
    /// @param len Maximum number of requests to return.
    /// @return requestsList Request structs.
    function getRequests(uint256 from, uint256 len) external view returns (Request[] memory);

    /// @notice Total count of outbound requests issued from this inbox.
    /// @return count Number of requests.
    function getRequestsLen() external view returns (uint256);

    /// @notice Remote chain ID and contract for the currently executing incoming message.
    /// @return chainId Remote chain ID.
    /// @return contractAddress Remote caller contract.
    function inboxMsgSender() external view returns (uint256 chainId, address contractAddress);

    /// @notice Request ID for the currently executing incoming message.
    /// @return requestId Active request ID.
    function inboxRequestId() external view returns (bytes32);

    /// @notice Source request ID linked from the current incoming message (if any).
    /// @return sourceRequestId Linked request ID.
    function inboxSourceRequestId() external view returns (bytes32);

    // --- External: pure ---

    /// @notice Pack chain ID and nonce (each up to 128 bits) into a request ID.
    /// @param chainId Chain ID half.
    /// @param nonce Nonce half.
    /// @return requestId 256-bit packed ID.
    function getRequestId(uint256 chainId, uint256 nonce) external pure returns (bytes32);

    /// @notice Split a packed request ID into chain ID and nonce.
    /// @param requestId Packed ID.
    /// @return chainId Chain ID half.
    /// @return nonce Nonce half.
    function unpackRequestId(bytes32 requestId) external pure returns (uint256 chainId, uint256 nonce);
}
