// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IInbox.sol";

contract InboxBase is IInbox {
    uint256 public immutable chainId;
    
    // Mapping from requestId to Request
    mapping(bytes32 => Request) public requests;
    
    // Mapping from requestId to Response
    mapping(bytes32 => Response) public responses;
    
    // Mapping from requestId to Error
    mapping(bytes32 => Error) public errors;
    
    // Current execution context for incoming messages (used during message execution)
    ExecutionContext internal _currentContext;
    
    // Request epoch for generating unique request IDs (starts at 1)
    uint256 internal _requestEpoch;
    
    // Incoming requests (requests that need to be delivered to target contracts on this chain)
    mapping(bytes32 => Request) public incomingRequests;
    
    // Mapping to track source contracts for incoming requests
    mapping(bytes32 => address) internal _requestSourceContracts;
    
    event MessageSent(
        bytes32 indexed requestId,
        uint256 indexed targetChainId,
        address indexed targetContract,
        bytes data,
        bytes4 callbackSelector,
        bytes4 errorSelector
    );
    
    event MessageReceived(
        bytes32 indexed requestId,
        uint256 indexed sourceChainId,
        address indexed sourceContract,
        bytes data
    );
    
    event ResponseReceived(
        bytes32 indexed requestId,
        bytes response
    );
    
    event ErrorReceived(
        bytes32 indexed requestId,
        uint64 errorCode,
        bytes errorMessage
    );

    constructor(uint256 _chainId) {
        chainId = _chainId;
    }

    /// @notice Sends a two-way message to a target chain with callback and error handlers
    /// @param targetChainId The chain ID of the target chain
    /// @param targetContract The address of the target contract on the target chain
    /// @param data The encoded function call data to send
    /// @param callbackSelector The function selector to call when response is received
    /// @param errorSelector The function selector to call when an error occurs
    /// @return requestId The unique request ID for this message
    function sendTwoWayMessage(
        uint256 targetChainId,
        address targetContract,
        bytes memory data,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) external virtual returns (bytes32) {
        return _sendTwoWayMessage(targetChainId, targetContract, data, callbackSelector, errorSelector);
    }
    
    function _sendTwoWayMessage(
        uint256 targetChainId,
        address targetContract,
        bytes memory data,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        require(targetChainId != chainId, "Inbox: cannot send to same chain");
        require(targetContract != address(0), "Inbox: invalid target contract");
        
        // Increment epoch (starts at 1)
        ++_requestEpoch;
        
        // Generate requestId from chainId and epoch
        bytes32 requestId = keccak256(abi.encodePacked(chainId, _requestEpoch));
        
        Request memory request = Request({
            requestId: requestId,
            targetChainId: targetChainId,
            targetContract: targetContract,
            data: data,
            callerContract: msg.sender,
            originalSender: msg.sender,
            timestamp: uint64(block.timestamp),
            callbackSelector: callbackSelector,
            errorSelector: errorSelector,
            isTwoWay: true,
            executed: false,
            sourceRequestId: bytes32(0) // Not a response
        });
        
        requests[requestId] = request;
        
        emit MessageSent(
            requestId,
            targetChainId,
            targetContract,
            data,
            callbackSelector,
            errorSelector
        );
        
        return requestId;
    }

    /// @notice Sends a one-way message to a target chain with only an error handler
    /// @param targetChainId The chain ID of the target chain
    /// @param targetContract The address of the target contract on the target chain
    /// @param data The encoded function call data to send
    /// @param errorSelector The function selector to call when an error occurs
    /// @return requestId The unique request ID for this message
    function sendOneWayMessage(
        uint256 targetChainId,
        address targetContract,
        bytes memory data,
        bytes4 errorSelector
    ) external returns (bytes32) {
        return _sendOneWayMessage(targetChainId, targetContract, data, errorSelector, bytes32(0));
    }
    
    function _sendOneWayMessage(
        uint256 targetChainId,
        address targetContract,
        bytes memory data,
        bytes4 errorSelector,
        bytes32 sourceRequestId
    ) internal returns (bytes32) {
        require(targetChainId != chainId, "Inbox: cannot send to same chain");
        require(targetContract != address(0), "Inbox: invalid target contract");
        
        // Increment epoch (starts at 1)
        ++_requestEpoch;
        
        // Generate requestId from chainId and epoch
        bytes32 requestId = keccak256(abi.encodePacked(chainId, _requestEpoch));
        
        Request memory request = Request({
            requestId: requestId,
            targetChainId: targetChainId,
            targetContract: targetContract,
            data: data,
            callerContract: msg.sender,
            originalSender: msg.sender,
            timestamp: uint64(block.timestamp),
            callbackSelector: bytes4(0), // No callback for one-way
            errorSelector: errorSelector, // Error handler for one-way
            isTwoWay: false,
            executed: false,
            sourceRequestId: sourceRequestId // Set if this is a response
        });
        
        requests[requestId] = request;
        
        emit MessageSent(
            requestId,
            targetChainId,
            targetContract,
            data,
            bytes4(0),
            errorSelector
        );
        
        return requestId;
    }

    /// @notice Gets error information for an outgoing request that failed
    /// @param requestId The request ID to get error information for
    /// @return code The error code
    /// @return message The error message
    function getOutboxError(bytes32 requestId) external view returns (uint256 code, string memory message) {
        Error memory err = errors[requestId];
        require(err.requestId != bytes32(0), "Inbox: error not found");
        return (err.errorCode, string(err.errorMessage));
    }

    /// @notice Gets the response data for an incoming request that was responded to
    /// @param requestId The request ID to get response data for
    /// @return The response data bytes
    function getInboxResponse(bytes32 requestId) external view returns (bytes memory) {
        Response memory response = responses[requestId];
        require(response.requestId != bytes32(0), "Inbox: response not found");
        return response.response;
    }

    /// @notice Gets the sender information for the currently executing message
    /// @dev Can only be called during message execution (when ExecutionContext is set)
    /// @return chainId_ The chain ID of the message sender
    /// @return contractAddress The contract address that sent the message
    function inboxMsgSender() external view returns (uint256 chainId_, address contractAddress) {
        require(_currentContext.remoteChainId != 0, "Inbox: no active message");
        require(_currentContext.requestId != bytes32(0), "Inbox: no active message");
        
        // Use _currentContext.remoteContract if set (for execution context), otherwise fall back to mapping
        address sourceContract = _currentContext.remoteContract;
        if (sourceContract == address(0)) {
            sourceContract = _requestSourceContracts[_currentContext.requestId];
        }
        
        return (_currentContext.remoteChainId, sourceContract);
    }

    /// @notice Responds to an incoming message by creating a one-way response request
    /// @dev Can only be called during message execution (when ExecutionContext is set)
    /// @param data The response data to send back to the source chain
    function respond(bytes memory data) external {
        require(_currentContext.requestId != bytes32(0), "Inbox: no active message");
        require(_currentContext.remoteChainId != 0, "Inbox: no active message");
        
        bytes32 sourceRequestId = _currentContext.requestId;
        Request storage incomingRequest = incomingRequests[sourceRequestId];
        require(incomingRequest.requestId != bytes32(0), "Inbox: request not found");
        // Note: executed flag is set by deliverMessage, not here
        
        // Create a new one-way request to send response back to source chain
        // Encode the response data and the original requestId for the callback
        bytes memory responseData = abi.encode(data, sourceRequestId);
        
        // Get the original sender contract from the incoming request
        // The originalSender is the contract on the source chain that sent the message
        address originalSenderContract = incomingRequest.originalSender;
        require(originalSenderContract != address(0), "Inbox: original sender not found");
        
        // Create one-way request with sourceRequestId set to link it back
        // Use the errorSelector from the original two-way request
        _sendOneWayMessage(
            _currentContext.remoteChainId,
            originalSenderContract,
            responseData,
            incomingRequest.errorSelector, // Use error handler from original request
            sourceRequestId // Link back to original request
        );
        
        // Store response mapping for getInboxResponse
        Response memory response = Response({
            requestId: sourceRequestId,
            response: data
        });
        responses[sourceRequestId] = response;
        
        emit ResponseReceived(sourceRequestId, data);
        
        // Clear execution context
        _currentContext = ExecutionContext({
            remoteChainId: 0,
            remoteContract: address(0),
            requestId: bytes32(0)
        });
    }

    /// @notice Generates a request ID from a chain ID and epoch
    /// @param chainId_ The chain ID
    /// @param epoch The request epoch number
    /// @return The generated request ID
    function getRequestId(uint chainId_, uint epoch) external view returns (bytes32) {
        return keccak256(abi.encodePacked(chainId_, epoch));
    }
    
    // Internal helper functions
    function _getOriginalSender(bytes32 requestId) internal view returns (address) {
        return requests[requestId].originalSender;
    }
    
    function _getSourceContractFromRequest(bytes32 requestId) internal view returns (address) {
        return _requestSourceContracts[requestId];
    }
}
