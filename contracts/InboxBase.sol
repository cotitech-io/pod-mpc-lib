// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IInbox.sol";
import "./mpccodec/MpcAbiCodec.sol";

contract InboxBase is IInbox {
    uint256 public immutable chainId;
    
    // Mapping from requestId to Request
    mapping(bytes32 => Request) public requests;
    
    // Mapping from requestId to Response
    mapping(bytes32 => Response) public inboxResponses;
    
    // Mapping from requestId to Error
    mapping(bytes32 => Error) public errors;
    
    // Current execution context for incoming messages (used during message execution)
    ExecutionContext internal _currentContext;
    
    // Request nonce for generating unique request IDs (starts at 1)
    uint256 internal _requestNonce;
    
    // Incoming requests (requests that need to be delivered to target contracts on this chain)
    mapping(bytes32 => Request) public incomingRequests;

    /// @notice Hook for tracking newly created outgoing requests
    /// @dev Override in Inbox to add requests to pending queues
    /// @param requestId The request ID that was created
    function _trackPendingRequest(bytes32 requestId) internal virtual {}
    
    event MessageSent(
        bytes32 indexed requestId,
        uint256 indexed targetChainId,
        address indexed targetContract,
        MpcMethodCall methodCall,
        bytes4 callbackSelector,
        bytes4 errorSelector
    );
    
    event MessageReceived(
        bytes32 indexed requestId,
        uint256 indexed sourceChainId,
        address indexed sourceContract,
        MpcMethodCall methodCall
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
    /// @dev If methodCall.selector is zero, methodCall.data must be full calldata
    ///      (abi.encodeWithSelector) and datatypes/datalens must be empty.
    /// @param targetChainId The chain ID of the target chain
    /// @param targetContract The address of the target contract on the target chain
    /// @param methodCall The method call to send
    /// @param callbackSelector The function selector to call when response is received
    /// @param errorSelector The function selector to call when an error occurs
    /// @return requestId The unique request ID for this message
    function sendTwoWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall calldata methodCall,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) external virtual returns (bytes32) {
        return _sendTwoWayMessage(targetChainId, targetContract, methodCall, callbackSelector, errorSelector);
    }
    
    function _sendTwoWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall memory methodCall,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        return _createRequest(
            targetChainId,
            targetContract,
            methodCall,
            callbackSelector,
            errorSelector,
            true,
            bytes32(0)
        );
    }

    /// @notice Sends a one-way message to a target chain with only an error handler
    /// @dev If methodCall.selector is zero, methodCall.data must be full calldata
    ///      (abi.encodeWithSelector) and datatypes/datalens must be empty.
    /// @param targetChainId The chain ID of the target chain
    /// @param targetContract The address of the target contract on the target chain
    /// @param methodCall The method call to send
    /// @param errorSelector The function selector to call when an error occurs
    /// @return requestId The unique request ID for this message
    function sendOneWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall calldata methodCall,
        bytes4 errorSelector
    ) external returns (bytes32) {
        return _sendOneWayMessage(targetChainId, targetContract, methodCall, errorSelector, bytes32(0));
    }
    
    function _sendOneWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall memory methodCall,
        bytes4 errorSelector,
        bytes32 sourceRequestId
    ) internal returns (bytes32) {
        return _createRequest(
            targetChainId,
            targetContract,
            methodCall,
            bytes4(0),
            errorSelector,
            false,
            sourceRequestId
        );
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
        Response memory response = inboxResponses[requestId];
        require(response.responseRequestId != bytes32(0), "Inbox: response not found");
        return response.response;
    }

    /// @notice Gets the sender information for the currently executing message
    /// @dev Can only be called during message execution (when ExecutionContext is set)
    /// @return chainId_ The chain ID of the message sender
    /// @return contractAddress The contract address that sent the message
    function inboxMsgSender() external view returns (uint256 chainId_, address contractAddress) {
        require(_currentContext.remoteChainId != 0, "Inbox: no active message");
        require(_currentContext.requestId != bytes32(0), "Inbox: no active message");
        
        return (_currentContext.remoteChainId, _currentContext.remoteContract);
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
        
        // Create a new one-way request to send response back to source chain
        MpcMethodCall memory responseMethodCall = MpcMethodCall({
            selector: bytes4(0),
            data: abi.encodeWithSelector(incomingRequest.callbackSelector, data),
            datatypes: new bytes8[](0),
            datalens: new bytes32[](0)
        });
        
        // Get the original sender contract from the incoming request
        // The originalSender is the contract on the source chain that sent the message
        address originalSenderContract = incomingRequest.originalSender;
        require(originalSenderContract != address(0), "Inbox: original sender not found");
        
        // Create one-way request with sourceRequestId set to link it back
        // Use the errorSelector from the original two-way request
        bytes32 responseRequestId = _sendOneWayMessage(
            _currentContext.remoteChainId,
            originalSenderContract,
            responseMethodCall,
            incomingRequest.errorSelector, // Use error handler from original request
            sourceRequestId // Link back to original request
        );
        
        // Store response mapping for getInboxResponse
        Response memory response = Response({
            responseRequestId: responseRequestId,
            response: data
        });
        inboxResponses[sourceRequestId] = response;
        
        emit ResponseReceived(sourceRequestId, data);
    }

    /// @notice Generates a request ID from a chain ID and nonce (128-bit each)
    /// @param chainId_ The chain ID (uint128)
    /// @param nonce The request nonce number (uint128)
    /// @return The generated request ID
    function getRequestId(uint chainId_, uint nonce) external pure returns (bytes32) {
        return _packRequestId(chainId_, nonce);
    }

    /// @notice Unpacks a request ID into chain ID and nonce (128-bit each)
    /// @param requestId The packed request ID
    /// @return chainId_ The chain ID (uint128)
    /// @return nonce The request nonce number (uint128)
    function unpackRequestId(bytes32 requestId) external pure returns (uint chainId_, uint nonce) {
        uint256 packed = uint256(requestId);
        chainId_ = uint256(uint128(packed >> 128));
        nonce = uint256(uint128(packed));
    }

    /// @notice Gets a range of outgoing requests by index
    /// @param from The starting index (0-based)
    /// @param len The number of requests to return
    /// @return A list of requests in nonce order
    function getRequests(uint from, uint len) external view returns (Request[] memory) {
        if (len == 0) {
            return new Request[](0);
        }

        uint total = _requestNonce;
        if (total == 0 || from >= total) {
            return new Request[](0);
        }

        uint endIndex = from + len;
        if (endIndex > total) {
            endIndex = total;
        }

        uint actualLen = endIndex - from;
        Request[] memory result = new Request[](actualLen);

        for (uint i = 0; i < actualLen; i++) {
            uint nonce = from + i + 1; // Nonce is 1-based; index is 0-based
            bytes32 requestId = _packRequestId(chainId, nonce);
            result[i] = requests[requestId];
        }

        return result;
    }

    /// @notice Gets the total number of outgoing requests
    function getRequestsLen() external view returns (uint) {
        return _requestNonce;
    }
    
    // Internal helper functions
    function _createRequest(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall memory methodCall,
        bytes4 callbackSelector,
        bytes4 errorSelector,
        bool isTwoWay,
        bytes32 sourceRequestId
    ) internal returns (bytes32) {
        require(targetChainId != chainId, "Inbox: cannot send to same chain");
        require(targetContract != address(0), "Inbox: invalid target contract");

        // Increment nonce (starts at 1)
        ++_requestNonce;

        // Generate requestId from chainId and nonce (128-bit each)
        bytes32 requestId = _packRequestId(chainId, _requestNonce);

        Request memory request = Request({
            requestId: requestId,
            targetChainId: targetChainId,
            targetContract: targetContract,
            methodCall: methodCall,
            callerContract: msg.sender,
            originalSender: msg.sender,
            timestamp: uint64(block.timestamp),
            callbackSelector: callbackSelector,
            errorSelector: errorSelector,
            isTwoWay: isTwoWay,
            executed: false,
            sourceRequestId: sourceRequestId
        });

        requests[requestId] = request;
        _trackPendingRequest(requestId);

        emit MessageSent(
            requestId,
            targetChainId,
            targetContract,
            methodCall,
            callbackSelector,
            errorSelector
        );

        return requestId;
    }

    function _packRequestId(uint chainId_, uint nonce) internal pure returns (bytes32) {
        require(chainId_ <= type(uint128).max, "Inbox: chainId too large");
        require(nonce <= type(uint128).max, "Inbox: nonce too large");
        return bytes32((uint256(uint128(chainId_)) << 128) | uint256(uint128(nonce)));
    }

    /// @notice Builds calldata for a request, supporting MPC re-encoding and a compact raw mode.
    /// @dev If selector is zero, data is assumed to be full calldata (abi.encodeWithSelector)
    ///      and datatypes/datalens must be empty. Otherwise, if datatypes are provided,
    ///      arguments are re-encoded to map it-* types to gt-* before dispatch.
    function _encodeMethodCall(MpcMethodCall memory methodCall) internal returns (bytes memory) {
        if (methodCall.selector == bytes4(0)) {
            require(methodCall.datatypes.length == 0, "Inbox: raw call has datatypes");
            require(methodCall.datalens.length == 0, "Inbox: raw call has datalens");
            return methodCall.data;
        }

        IInbox.MpcMethodCall memory codecCall = IInbox.MpcMethodCall({
            selector: methodCall.selector,
            data: methodCall.data,
            datatypes: methodCall.datatypes,
            datalens: methodCall.datalens
        });

        return MpcAbiCodec.reEncodeWithGt(codecCall);
    }
    function _getOriginalSender(bytes32 requestId) internal view returns (address) {
        return requests[requestId].originalSender;
    }
    
}
