// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./fee/InboxFeeManager.sol";
import "./IInbox.sol";
import "./mpccodec/MpcAbiCodec.sol";

/// @title InboxBase
/// @notice Core inbox: outbound requests, inbound execution context, responses, errors, and MPC calldata encoding.
/// @dev Mixed with {InboxFeeManager}. Subcontracts add miner and ownership behavior.
contract InboxBase is IInbox, InboxFeeManager {
    /// @notice This chain's ID (deploy-time; may differ from `block.chainid` when `_chainId` is non-zero).
    uint256 public chainId;

    mapping(bytes32 => Request) public requests;
    mapping(bytes32 => Response) public inboxResponses;
    mapping(bytes32 => Error) public errors;
    mapping(bytes32 => Request) public incomingRequests;
    mapping(uint256 => bytes32) public lastIncomingRequestId;

    ExecutionContext internal _currentContext;
    uint256 internal _requestNonce;

    uint64 internal constant ERROR_CODE_EXECUTION_FAILED = 1;
    uint64 internal constant ERROR_CODE_ENCODE_FAILED = 2;

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

    event ResponseReceived(bytes32 indexed requestId, bytes response);

    event RaiseReceived(bytes32 indexed incomingRequestId, bytes errorPayload);

    event IncomingResponseReceived(bytes32 indexed requestId, bytes32 indexed sourceRequestId);

    event ErrorReceived(bytes32 indexed requestId, uint64 errorCode, bytes errorMessage);

    /// @notice Emitted after executing an incoming request. Values are gas units (same basis as `Request.targetFee`).
    /// @param gasUsed Gas used by the subcall (approximate).
    /// @param gasRemainingApprox Remaining gas budget from `targetFee` after the subcall (floored at zero).
    event FeeExecutionSettled(bytes32 indexed requestId, uint256 gasUsed, uint256 gasRemainingApprox);

    /// @param _chainId This chain's ID; pass `0` to use `block.chainid`.
    constructor(uint256 _chainId) {
        chainId = _chainId == 0 ? block.chainid : _chainId;
    }

    /// @inheritdoc IInbox
    function sendTwoWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall calldata methodCall,
        bytes4 callbackSelector,
        bytes4 errorSelector,
        uint256 callbackFeeLocalWei
    ) external payable virtual returns (bytes32) {
        uint256 dataSize = abi.encode(methodCall).length;
        (uint256 targetFeeGas, uint256 callerFeeGas) =
            validateAndPrepareTwoWayFees(dataSize, msg.value, callbackFeeLocalWei);
        return _sendTwoWayMessage(
            targetChainId, targetContract, methodCall, callbackSelector, errorSelector, targetFeeGas, callerFeeGas
        );
    }

    /// @inheritdoc IInbox
    function sendOneWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall calldata methodCall,
        bytes4 errorSelector
    ) external payable returns (bytes32) {
        uint256 dataSize = abi.encode(methodCall).length;
        uint256 targetFeeGas = validateAndPrepareOneWayFees(dataSize, msg.value);
        return _sendOneWayMessage(targetChainId, targetContract, methodCall, errorSelector, bytes32(0), targetFeeGas, 0);
    }

    /// @inheritdoc IInbox
    function respond(bytes memory data) external {
        require(_currentContext.requestId != bytes32(0), "Inbox: no active message");
        require(_currentContext.remoteChainId != 0, "Inbox: no active message");

        bytes32 incomingRequestId = _currentContext.requestId;
        require(inboxResponses[incomingRequestId].responseRequestId == bytes32(0), "Inbox: reply already sent");

        Request storage incomingRequest = incomingRequests[incomingRequestId];
        require(incomingRequest.requestId != bytes32(0), "Inbox: request not found");

        MpcMethodCall memory responseMethodCall = MpcMethodCall({
            selector: bytes4(0),
            data: abi.encodeWithSelector(incomingRequest.callbackSelector, data),
            datatypes: new bytes8[](0),
            datalens: new bytes32[](0)
        });

        address originalSenderContract = incomingRequest.originalSender;
        require(originalSenderContract != address(0), "Inbox: original sender not found");

        bytes32 responseRequestId = _sendOneWayMessage(
            _currentContext.remoteChainId,
            originalSenderContract,
            responseMethodCall,
            incomingRequest.errorSelector,
            incomingRequestId,
            incomingRequest.callerFee,
            0
        );

        inboxResponses[incomingRequestId] = Response({responseRequestId: responseRequestId, response: data});

        emit ResponseReceived(incomingRequestId, data);
    }

    /// @inheritdoc IInbox
    function raise(bytes memory data) external {
        require(_currentContext.requestId != bytes32(0), "Inbox: no active message");
        require(_currentContext.remoteChainId != 0, "Inbox: no active message");

        bytes32 incomingRequestId = _currentContext.requestId;
        require(inboxResponses[incomingRequestId].responseRequestId == bytes32(0), "Inbox: reply already sent");

        Request storage incomingRequest = incomingRequests[incomingRequestId];
        require(incomingRequest.requestId != bytes32(0), "Inbox: request not found");
        require(incomingRequest.errorSelector != bytes4(0), "Inbox: no error handler");

        MpcMethodCall memory errorMethodCall = MpcMethodCall({
            selector: bytes4(0),
            data: abi.encodeWithSelector(incomingRequest.errorSelector, data),
            datatypes: new bytes8[](0),
            datalens: new bytes32[](0)
        });

        address originalSenderContract = incomingRequest.originalSender;
        require(originalSenderContract != address(0), "Inbox: original sender not found");

        bytes32 outboundRequestId = _sendOneWayMessage(
            _currentContext.remoteChainId,
            originalSenderContract,
            errorMethodCall,
            incomingRequest.errorSelector,
            incomingRequestId,
            incomingRequest.callerFee,
            0
        );

        inboxResponses[incomingRequestId] = Response({responseRequestId: outboundRequestId, response: data});

        emit RaiseReceived(incomingRequestId, data);
    }

    /// @inheritdoc IInbox
    function getOutboxError(bytes32 requestId) external view returns (uint256 code, string memory message) {
        Error memory err = errors[requestId];
        require(err.requestId != bytes32(0), "Inbox: error not found");
        return (err.errorCode, string(err.errorMessage));
    }

    /// @inheritdoc IInbox
    function getInboxResponse(bytes32 requestId) external view returns (bytes memory) {
        Response memory response = inboxResponses[requestId];
        require(response.responseRequestId != bytes32(0), "Inbox: response not found");
        return response.response;
    }

    /// @inheritdoc IInbox
    function getRequests(uint256 from, uint256 len) external view returns (Request[] memory) {
        if (len == 0) {
            return new Request[](0);
        }

        uint256 total = _requestNonce;
        if (total == 0 || from >= total) {
            return new Request[](0);
        }

        uint256 endIndex = from + len;
        if (endIndex > total) {
            endIndex = total;
        }

        uint256 actualLen = endIndex - from;
        Request[] memory result = new Request[](actualLen);

        for (uint256 i = 0; i < actualLen; i++) {
            uint256 nonce = from + i + 1;
            bytes32 requestId = _packRequestId(chainId, nonce);
            result[i] = requests[requestId];
        }

        return result;
    }

    /// @inheritdoc IInbox
    function getRequestsLen() external view returns (uint256) {
        return _requestNonce;
    }

    /// @inheritdoc IInbox
    function inboxMsgSender() external view returns (uint256 chainId_, address contractAddress) {
        require(_currentContext.remoteChainId != 0, "Inbox: no active message");
        require(_currentContext.requestId != bytes32(0), "Inbox: no active message");

        return (_currentContext.remoteChainId, _currentContext.remoteContract);
    }

    /// @inheritdoc IInbox
    function inboxRequestId() external view returns (bytes32) {
        require(_currentContext.requestId != bytes32(0), "Inbox: no active message");
        return _currentContext.requestId;
    }

    /// @inheritdoc IInbox
    function inboxSourceRequestId() external view returns (bytes32) {
        require(_currentContext.requestId != bytes32(0), "Inbox: no active message");
        return incomingRequests[_currentContext.requestId].sourceRequestId;
    }

    /// @inheritdoc IInbox
    function getRequestId(uint256 chainId_, uint256 nonce) external pure returns (bytes32) {
        return _packRequestId(chainId_, nonce);
    }

    /// @inheritdoc IInbox
    function unpackRequestId(bytes32 requestId) external pure returns (uint256 chainId_, uint256 nonce) {
        return _unpackRequestId(requestId);
    }

    /// @dev Exposed for try/catch around {_encodeMethodCall}; self-call only.
    function _encodeMethodCallExternal(MpcMethodCall calldata methodCall) external returns (bytes memory) {
        require(msg.sender == address(this), "Inbox: only self");
        return _encodeMethodCall(methodCall);
    }

    /// @dev Creates a two-way outbound request.
    function _sendTwoWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall memory methodCall,
        bytes4 callbackSelector,
        bytes4 errorSelector,
        uint256 targetFeeGas,
        uint256 callerFeeGas
    ) internal returns (bytes32) {
        return _createRequest(
            targetChainId,
            targetContract,
            methodCall,
            callbackSelector,
            errorSelector,
            true,
            bytes32(0),
            targetFeeGas,
            callerFeeGas
        );
    }

    /// @dev Creates a one-way outbound request (including responses/errors).
    function _sendOneWayMessage(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall memory methodCall,
        bytes4 errorSelector,
        bytes32 sourceRequestId,
        uint256 targetFeeGas,
        uint256 callerFeeGas
    ) internal returns (bytes32) {
        return _createRequest(
            targetChainId,
            targetContract,
            methodCall,
            bytes4(0),
            errorSelector,
            false,
            sourceRequestId,
            targetFeeGas,
            callerFeeGas
        );
    }

    /// @dev Creates and stores a request and emits {MessageSent}.
    function _createRequest(
        uint256 targetChainId,
        address targetContract,
        MpcMethodCall memory methodCall,
        bytes4 callbackSelector,
        bytes4 errorSelector,
        bool isTwoWay,
        bytes32 sourceRequestId,
        uint256 targetFeeGas,
        uint256 callerFeeGas
    ) internal returns (bytes32) {
        require(targetChainId != chainId, "Inbox: cannot send to same chain");
        require(targetContract != address(0), "Inbox: invalid target contract");

        ++_requestNonce;

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
            sourceRequestId: sourceRequestId,
            targetFee: targetFeeGas,
            callerFee: callerFeeGas
        });

        requests[requestId] = request;

        emit MessageSent(requestId, targetChainId, targetContract, methodCall, callbackSelector, errorSelector);
        priceOracle.fetchPrices();
        return requestId;
    }

    /// @dev Packs `chainId` and `nonce` (each 128 bits) into a `bytes32` request ID.
    function _packRequestId(uint256 chainId_, uint256 nonce) internal pure returns (bytes32) {
        require(chainId_ <= type(uint128).max, "Inbox: chainId too large");
        require(nonce <= type(uint128).max, "Inbox: nonce too large");
        return bytes32((uint256(uint128(chainId_)) << 128) | uint256(uint128(nonce)));
    }

    /// @dev Unpacks a request ID from {_packRequestId}.
    function _unpackRequestId(bytes32 requestId) internal pure returns (uint256 chainId_, uint256 nonce) {
        uint256 packed = uint256(requestId);
        chainId_ = uint256(uint128(packed >> 128));
        nonce = uint256(uint128(packed));
    }

    /// @dev Raw calldata passthrough if selector is zero; otherwise MPC re-encode via {MpcAbiCodec}.
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

    /// @dev Non-reverting encode wrapper for inbound execution.
    function _safeEncodeMethodCall(MpcMethodCall memory methodCall)
        internal
        returns (bool ok, bytes memory callData, bytes memory err)
    {
        try this._encodeMethodCallExternal(methodCall) returns (bytes memory data) {
            return (true, data, new bytes(0));
        } catch (bytes memory reason) {
            return (false, new bytes(0), reason);
        }
    }

    /// @dev Records an encode failure and emits {ErrorReceived}.
    function _recordEncodeError(bytes32 requestId, bytes memory encodeErr) internal {
        bytes memory errorMessage = encodeErr.length == 0
            ? abi.encodePacked("Inbox: encodeMethodCall failed")
            : encodeErr;
        Error memory err = Error({
            requestId: requestId,
            errorCode: ERROR_CODE_ENCODE_FAILED,
            errorMessage: errorMessage
        });
        errors[requestId] = err;
        emit ErrorReceived(requestId, ERROR_CODE_ENCODE_FAILED, errorMessage);
    }

    /// @dev Original sender for an outbound `requestId`.
    function _getOriginalSender(bytes32 requestId) internal view returns (address) {
        return requests[requestId].originalSender;
    }
}
