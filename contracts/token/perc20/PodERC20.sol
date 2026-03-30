// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../InboxUser.sol";
import "../../mpccodec/MpcAbiCodec.sol";
import "./IPodERC20.sol";
import "./cotiside/IPodErc20CotiSide.sol";

/// @title PodERC20
/// @notice PoD-side private ERC-20: ciphertext cache and inbox-mediated async moves; COTI holds authoritative garbled state via {IPodErc20CotiSide}.
/// @dev Callbacks only from `inbox` when the remote peer matches (`cotiChainId`, `cotiSideContract`). `setPublicAmountsEnabled` is not access-controlled—harden for production.
contract PodERC20 is IPodERC20, InboxUser {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    // --- State variables ---

    uint256 public immutable cotiChainId;
    address public immutable cotiSideContract;
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => ctUint256) private _balances;
    mapping(address => mapping(address => IPodERC20.Allowance)) private _allowance;
    /// @dev One in-flight transfer or burn per address (used as both sender and receiver lock for transfers).
    mapping(address => bytes32) private _pendingTransferRequestIds;
    mapping(address => mapping(address => bytes32)) private _pendingApprovalRequestIds;
    bool private _publicAmountsEnabled;
    /// @dev Optional `transferAndCall` payload keyed by inbox `sourceRequestId`, cleared after callback.
    mapping(bytes32 => bytes) private _requestCallbacks;
    mapping(bytes32 => bytes) public failedRequests;
    /// @dev Monotonic nonce from COTI; stale callbacks do not overwrite newer balances.
    mapping(address => uint256) public balanceNonces;

    // --- Events (PoD-specific; {Transfer}, {Approval}, etc. are declared on {IPodERC20}) ---

    event TransferRequestSubmitted(address indexed from, address indexed to, bytes32 requestId);
    event ApprovalRequestSubmitted(address indexed owner, address indexed spender, bytes32 requestId);
    event ApprovalFailed(address indexed owner, address indexed spender, bytes errorMsg);
    event SyncBalancesFailed(bytes32 requestId, bytes errorMsg);
    event SyncBalancesRequested(address[] accounts, bytes32 requestId);

    // --- Errors ---

    error TransferAlreadyPending(address from, address to, bytes32 requestId);
    error ApprovalAlreadyPending(address owner, address spender, bytes32 requestId);
    error OnlyCotiSideContract(uint256 remoteChainId, address remoteContract);

    // --- Constructor ---

    /**
     * @param _cotiChainId Chain id of COTI; must match {IInbox.inboxMsgSender} when the peer calls back.
     * @param _inbox Cross-chain inbox used for two-way messages (also sets {InboxUser.inbox}).
     * @param _cotiSideContract Deployed {IPodErc20CotiSide} this token talks to on COTI.
     * @param _name ERC-20 name string (public metadata on PoD).
     * @param _symbol ERC-20 symbol string (public metadata on PoD).
     */
    constructor(
        uint256 _cotiChainId,
        address _inbox,
        address _cotiSideContract,
        string memory _name,
        string memory _symbol
    ) {
        setInbox(_inbox);
        cotiSideContract = _cotiSideContract;
        name = _name;
        symbol = _symbol;
        decimals = 18;
        totalSupply = 0;
        cotiChainId = _cotiChainId;
    }

    receive() external payable {}

    // --- External: mutating (user / admin) ---

    /**
     * @notice Toggles whether future plain-uint amount helpers (if you add them) should be allowed.
     * @dev **Gotcha:** callable by any address; add `onlyOwner` (or similar) if this must be admin-only.
     */
    function setPublicAmountsEnabled(bool enabled) external {
        _publicAmountsEnabled = enabled;
    }

    /**
     * @inheritdoc IPodERC20
     * @dev **Gotcha:** reverts if either party already has a pending transfer. **Gotcha:** `TransferRequestSubmitted` indexes
     *      `msg.sender` as `from`, not the `from` argument of internal `_transfer` (same for direct `transfer`).
     */
    function transfer(address to, itUint256 calldata value, uint256 callbackFeeLocalWei) external payable returns (bytes32 requestId) {
        return _transfer(IPodErc20CotiSide.transfer.selector, msg.sender, to, value, msg.value, callbackFeeLocalWei);
    }

    /// @inheritdoc IPodERC20
    function transferFrom(address from, address to, itUint256 calldata value, uint256 callbackFeeLocalWei) external payable returns (bytes32 requestId) {
        return _transfer(IPodErc20CotiSide.transferFrom.selector, from, to, value, msg.value, callbackFeeLocalWei);
    }

    /**
     * @inheritdoc IPodERC20
     * @dev Stores `data` under the new `requestId` until {transferCallback} runs successfully and forwards it to `to`.
     */
    function transferAndCall(
        address to,
        itUint256 calldata amount,
        bytes calldata data,
        uint256 callbackFeeLocalWei
    ) external payable returns (bytes32 requestId) {
        requestId = _transfer(IPodErc20CotiSide.transfer.selector, msg.sender, to, amount, msg.value, callbackFeeLocalWei);
        _requestCallbacks[requestId] = data;
        return requestId;
    }

    /// @inheritdoc IPodERC20
    function approve(address spender, itUint256 calldata value, uint256 callbackFeeLocalWei) external payable returns (bytes32 requestId) {
        return _approve(msg.sender, spender, value, msg.value, callbackFeeLocalWei);
    }

    /// @inheritdoc IPodERC20
    function burn(itUint256 calldata value, uint256 callbackFeeLocalWei) external payable returns (bytes32 requestId) {
        return _burn(msg.sender, value, msg.value, callbackFeeLocalWei);
    }

    /**
     * @inheritdoc IPodERC20
     * @dev Does not record a “pending” flag per account for sync; only transfers/burns use the pending-transfer map.
     */
    function syncBalances(address[] calldata accounts, uint256 callbackFeeLocalWei) external payable returns (bytes32 requestId) {
        IInbox.MpcMethodCall memory mpcMethodCall = MpcAbiCodec.create(IPodErc20CotiSide.syncBalances.selector, 1)
            .addArgument(accounts)
            .build();

        requestId = _sendPodTwoWay(
            msg.value,
            callbackFeeLocalWei,
            mpcMethodCall,
            PodERC20.syncBalancesCallback.selector,
            PodERC20.syncBalancesError.selector
        );
        emit SyncBalancesRequested(accounts, requestId);
    }

    // --- External: inbox callbacks (success) ---

    /**
     * @notice Applies post-transfer ciphertext balances and optional `transferAndCall` hook.
     * @dev **Gotcha:** balance updates apply only when `nonce` exceeds {balanceNonces}; replays with old nonces are ignored.
     *      **Gotcha:** `to.call(callbackData)` uses all remaining gas; failures emit {RequestCallbackFailed} only.
     */
    function transferCallback(bytes memory data) external onlyInbox {
        (uint256 remoteChainId, address remoteContract) = inbox.inboxMsgSender();
        if (remoteChainId != cotiChainId || remoteContract != cotiSideContract) {
            revert OnlyCotiSideContract(remoteChainId, remoteContract);
        }
        bytes32 sourceRequestId = inbox.inboxSourceRequestId();
        (
            address from,
            ctUint256 memory newBalanceFrom,
            ctUint256 memory senderValue,
            address to,
            ctUint256 memory newBalanceTo,
            ctUint256 memory receiverValue,
            uint256 nonce
        ) = abi.decode(data, (address, ctUint256, ctUint256, address, ctUint256, ctUint256, uint256));
        if (from != address(0)) {
            _pendingTransferRequestIds[from] = bytes32(0);
            if (balanceNonces[from] < nonce) {
                _balances[from] = newBalanceFrom;
                balanceNonces[from] = nonce;
            }
        }
        if (to != address(0)) {
            _pendingTransferRequestIds[to] = bytes32(0);
            if (balanceNonces[to] < nonce) {
                _balances[to] = newBalanceTo;
                balanceNonces[to] = nonce;
            }
        }
        bytes memory callbackData = _requestCallbacks[sourceRequestId];
        emit Transfer(from, to, senderValue, receiverValue);
        if (callbackData.length != 0) {
            delete _requestCallbacks[sourceRequestId];
            (bool success, ) = address(to).call(callbackData);
            if (!success) {
                emit RequestCallbackFailed(from, to, sourceRequestId, callbackData);
            }
        }
    }

    /**
     * @notice Writes new allowance ciphertext after COTI approved the request.
     * @dev Clears the pending approval slot for `(owner, spender)`.
     */
    function approveCallback(bytes memory data) external onlyInbox {
        (uint256 remoteChainId, address remoteContract) = inbox.inboxMsgSender();
        if (remoteChainId != cotiChainId || remoteContract != cotiSideContract) {
            revert OnlyCotiSideContract(remoteChainId, remoteContract);
        }
        (address owner, ctUint256 memory ownerAmount, address spender, ctUint256 memory spenderAmount) = abi.decode(
            data,
            (address, ctUint256, address, ctUint256)
        );
        _pendingApprovalRequestIds[owner][spender] = bytes32(0);
        _allowance[owner][spender] = Allowance({spenderCiphertext: spenderAmount, ownerCiphertext: ownerAmount});
        emit Approval(owner, spender, ownerAmount, spenderAmount);
    }

    /**
     * @notice Applies batched balance ciphertexts from COTI after `syncBalances`.
     * @dev Per-account update only if `nonce` is newer than {balanceNonces}; emits {BalanceSynced} for each update applied.
     */
    function syncBalancesCallback(bytes memory data) external onlyInbox {
        (uint256 remoteChainId, address remoteContract) = inbox.inboxMsgSender();
        if (remoteChainId != cotiChainId || remoteContract != cotiSideContract) {
            revert OnlyCotiSideContract(remoteChainId, remoteContract);
        }
        (address[] memory addresses, ctUint256[] memory amounts, uint256 nonce) = abi.decode(
            data,
            (address[], ctUint256[], uint256)
        );
        for (uint256 i = 0; i < addresses.length; i++) {
            if (balanceNonces[addresses[i]] < nonce) {
                _balances[addresses[i]] = amounts[i];
                balanceNonces[addresses[i]] = nonce;
                emit BalanceSynced(addresses[i], amounts[i]);
            }
        }
    }

    // --- External: inbox callbacks (errors) ---

    /**
     * @notice Clears pending transfer state and records `failedRequests` for this `sourceRequestId`.
     * @dev **Gotcha:** when both `from` and `to` were locked, both are cleared; `TransferFailed` carries decoded addresses.
     */
    function transferError(bytes memory data) external onlyInbox {
        (uint256 remoteChainId, address remoteContract) = inbox.inboxMsgSender();
        if (remoteChainId != cotiChainId || remoteContract != cotiSideContract) {
            revert OnlyCotiSideContract(remoteChainId, remoteContract);
        }
        (address from, address to, bytes memory errorMsg) = abi.decode(data, (address, address, bytes));
        bytes32 sourceRequestId = inbox.inboxSourceRequestId();
        failedRequests[sourceRequestId] = errorMsg;
        if (from != address(0)) {
            _pendingTransferRequestIds[from] = bytes32(0);
        }
        _pendingTransferRequestIds[to] = bytes32(0);
        emit TransferFailed(from, to, errorMsg);
    }

    /// @notice Clears pending approval and surfaces COTI error bytes to listeners and {failedRequests}.
    function approveError(bytes memory data) external onlyInbox {
        (uint256 remoteChainId, address remoteContract) = inbox.inboxMsgSender();
        if (remoteChainId != cotiChainId || remoteContract != cotiSideContract) {
            revert OnlyCotiSideContract(remoteChainId, remoteContract);
        }
        (address owner, address spender, bytes memory errorMsg) = abi.decode(data, (address, address, bytes));
        bytes32 sourceRequestId = inbox.inboxSourceRequestId();
        failedRequests[sourceRequestId] = errorMsg;
        _pendingApprovalRequestIds[owner][spender] = bytes32(0);
        emit ApprovalFailed(owner, spender, errorMsg);
    }

    /// @notice `syncBalances` failed on COTI; `data` is forwarded into {SyncBalancesFailed} for debugging.
    function syncBalancesError(bytes memory data) external onlyInbox {
        (uint256 remoteChainId, address remoteContract) = inbox.inboxMsgSender();
        if (remoteChainId != cotiChainId || remoteContract != cotiSideContract) {
            revert OnlyCotiSideContract(remoteChainId, remoteContract);
        }
        bytes32 sourceRequestId = inbox.inboxSourceRequestId();
        emit SyncBalancesFailed(sourceRequestId, data);
    }

    // --- External: views ---

    /// @inheritdoc IPodERC20
    function publicAmountsEnabled() external view returns (bool) {
        return _publicAmountsEnabled;
    }

    /// @inheritdoc IPodERC20
    function balanceOf(address account) external view returns (ctUint256 memory) {
        return _balances[account];
    }

    /// @inheritdoc IPodERC20
    function balanceOfWithStatus(address account) external view returns (ctUint256 memory, bool pending) {
        return (_balances[account], _pendingTransferRequestIds[account] != bytes32(0));
    }

    /// @inheritdoc IPodERC20
    function allowance(address owner, address spender) external view returns (Allowance memory) {
        return _allowance[owner][spender];
    }

    /// @inheritdoc IPodERC20
    function allowanceWithStatus(
        address owner,
        address spender
    ) external view returns (Allowance memory, bool pending) {
        return (_allowance[owner][spender], _pendingApprovalRequestIds[owner][spender] != bytes32(0));
    }

    // --- Internal ---

    /// @param totalValueWei Total native payment (e.g. `msg.value`); `callbackFeeLocalWei` is the caller-supplied callback slice.
    function _sendPodTwoWay(
        uint256 totalValueWei,
        uint256 callbackFeeLocalWei,
        IInbox.MpcMethodCall memory mpcMethodCall,
        bytes4 callbackSelector_,
        bytes4 errorSelector_
    ) internal returns (bytes32) {
        require(callbackFeeLocalWei >= 1, "PodERC20: callback fee min");
        require(callbackFeeLocalWei <= totalValueWei, "PodERC20: callback exceeds total");
        require(address(this).balance >= totalValueWei, "PodERC20: inbox fee");
        return IInbox(inbox).sendTwoWayMessage{value: totalValueWei}(
            cotiChainId,
            cotiSideContract,
            mpcMethodCall,
            callbackSelector_,
            errorSelector_,
            callbackFeeLocalWei
        );
    }

    function _approve(address owner, address spender, itUint256 calldata value, uint256 totalValueWei, uint256 callbackFeeLocalWei) internal returns (bytes32 requestId) {
        if (_pendingApprovalRequestIds[owner][spender] != bytes32(0)) {
            revert ApprovalAlreadyPending(owner, spender, _pendingApprovalRequestIds[owner][spender]);
        }
        IInbox.MpcMethodCall memory mpcMethodCall = MpcAbiCodec.create(IPodErc20CotiSide.approve.selector, 3)
            .addArgument(owner)
            .addArgument(spender)
            .addArgument(value)
            .build();

        requestId = _sendPodTwoWay(
            totalValueWei,
            callbackFeeLocalWei,
            mpcMethodCall,
            PodERC20.approveCallback.selector,
            PodERC20.approveError.selector
        );
        _pendingApprovalRequestIds[owner][spender] = requestId;
        emit ApprovalRequestSubmitted(owner, spender, requestId);
    }

    function _burn(address from, itUint256 calldata value, uint256 totalValueWei, uint256 callbackFeeLocalWei) internal returns (bytes32 requestId) {
        if (_pendingTransferRequestIds[from] != bytes32(0)) {
            revert TransferAlreadyPending(from, address(0), _pendingTransferRequestIds[from]);
        }

        IInbox.MpcMethodCall memory mpcMethodCall = MpcAbiCodec.create(IPodErc20CotiSide.burn.selector, 2)
            .addArgument(from)
            .addArgument(value)
            .build();

        requestId = _sendPodTwoWay(
            totalValueWei,
            callbackFeeLocalWei,
            mpcMethodCall,
            PodERC20.transferCallback.selector,
            PodERC20.transferError.selector
        );

        _pendingTransferRequestIds[from] = requestId;
        emit TransferRequestSubmitted(from, address(0), requestId);
    }

    /**
     * @dev **Gotcha:** `TransferAlreadyPending` carries `_pendingTransferRequestIds[from]` even when `to` was the party that
     *      was actually pending—inspect both sides off-chain when debugging reverts.
     */
    function _transfer(
        bytes4 remoteTransferSelector,
        address from,
        address to,
        itUint256 calldata value,
        uint256 totalValueWei,
        uint256 callbackFeeLocalWei
    ) internal returns (bytes32 requestId) {
        if (_pendingTransferRequestIds[from] != bytes32(0) || _pendingTransferRequestIds[to] != bytes32(0)) {
            revert TransferAlreadyPending(from, to, _pendingTransferRequestIds[from]);
        }

        IInbox.MpcMethodCall memory mpcMethodCall = MpcAbiCodec.create(remoteTransferSelector, 3)
            .addArgument(from)
            .addArgument(to)
            .addArgument(value)
            .build();

        requestId = _sendPodTwoWay(
            totalValueWei,
            callbackFeeLocalWei,
            mpcMethodCall,
            PodERC20.transferCallback.selector,
            PodERC20.transferError.selector
        );
        _pendingTransferRequestIds[from] = requestId;
        _pendingTransferRequestIds[to] = requestId;
        emit TransferRequestSubmitted(msg.sender, to, requestId);
    }
}
