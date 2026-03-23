
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "./IPodERC20.sol";
import "../../InboxUser.sol";
import "../../mpccodec/MpcAbiCodec.sol";
import "./cotiside/IPodErc20CotiSide.sol";

contract PodERC20 is IPodERC20, InboxUser {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    error TransferAlreadyPending(address from, address to, bytes32 requestId);
    error ApprovalAlreadyPending(address owner, address spender, bytes32 requestId);
    error OnlyCotiSideContract(uint256 remoteChainId, address remoteContract);
    event TransferRequestSubmitted(address indexed from, address indexed to, bytes32 requestId);
    event ApprovalRequestSubmitted(address indexed owner, address indexed spender, bytes32 requestId);
    event ApprovalFailed(address indexed owner, address indexed spender, bytes errorMsg);
    event SyncBalancesFailed(bytes32 requestId, bytes errorMsg);
    event SyncBalancesRequested(address[] accounts, bytes32 requestId);

    uint256 public immutable cotiChainId;
    address public immutable cotiSideContract;
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => ctUint256) private _balances;
    mapping(address => mapping(address => IPodERC20.Allowance)) private _allowance;
    mapping(address => bytes32) private _pendingTransferRequstIds;
    mapping(address => mapping(address => bytes32)) private _pendingApprovalRequestIds;
    bool private _publicAmountsEnabled;
    mapping(bytes32 => bytes) private _requestCallbacks;
    mapping(bytes32 => bytes) public failedRequests;

    constructor(uint256 _cotiChainId, address _inbox, address _cotiSideContract, string memory _name, string memory _symbol) {
        setInbox(_inbox);
        cotiSideContract = _cotiSideContract;
        name = _name;
        symbol = _symbol;
        decimals = 18;
        totalSupply = 0;
        cotiChainId = _cotiChainId;
    }

    function publicAmountsEnabled() external view returns (bool) {
        return _publicAmountsEnabled;
    }

    function setPublicAmountsEnabled(bool enabled) external {
        _publicAmountsEnabled = enabled;
    }

    function balanceOf(
        address account
    ) external view returns (ctUint256 memory) {
        return _balances[account];
    }

    function balanceOfWithStatus(
        address account
    ) external view returns (ctUint256 memory, bool pending) {
        return (_balances[account], _pendingTransferRequstIds[account] != bytes32(0));
    }

    function transfer(address to, itUint256 calldata value) external returns (bytes32 requestId) {
        return _transfer(IPodErc20CotiSide.transfer.selector, msg.sender, to, value);
    }

    function transferFrom(address from, address to, itUint256 calldata value) external returns (bytes32 requestId) {
        return _transfer(IPodErc20CotiSide.transferFrom.selector, from, to, value);
    }

    function transferAndCall(
        address to,
        itUint256 calldata amount,
        bytes calldata data
    ) external returns (bytes32 requestId) {
        requestId = _transfer(IPodErc20CotiSide.transfer.selector, msg.sender, to, amount);
        _requestCallbacks[requestId] = data;
        return requestId;
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (Allowance memory) {
        return _allowance[owner][spender];
    }

    function allowanceWithStatus(
        address owner,
        address spender
    ) external view returns (Allowance memory, bool pending) {
        return (_allowance[owner][spender], _pendingApprovalRequestIds[owner][spender] != bytes32(0));
    }

    function approve(
        address spender,
        itUint256 calldata value
    ) external returns (bytes32 requestId) {
        return _approve(msg.sender, spender, value);
    }

    function burn(itUint256 calldata value) external returns (bytes32 requestId) {
        return _burn(msg.sender, value);
    }


    function syncBalances(address[] calldata accounts) external returns (bytes32 requestId) {
        IInbox.MpcMethodCall memory mpcMethodCall =
            MpcAbiCodec.create(IPodErc20CotiSide.syncBalances.selector, 1)
            .addArgument(accounts)
            .build();

        requestId = IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            cotiSideContract,
            mpcMethodCall,
            PodERC20.syncBalancesCallback.selector,
            PodERC20.syncBalancesError.selector
        );
        emit SyncBalancesRequested(accounts, requestId);
    }

    function _approve(
        address owner,
        address spender,
        itUint256 calldata value
    ) internal returns (bytes32 requestId) {
        if (_pendingApprovalRequestIds[owner][spender] != bytes32(0)) {
            revert ApprovalAlreadyPending(owner, spender, _pendingApprovalRequestIds[owner][spender]);
        }
        IInbox.MpcMethodCall memory mpcMethodCall =
            MpcAbiCodec.create(IPodErc20CotiSide.approve.selector, 3)
            .addArgument(owner)
            .addArgument(spender)
            .addArgument(value)
            .build();

        requestId = IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            cotiSideContract,
            mpcMethodCall,
            PodERC20.approveCallback.selector,
            PodERC20.approveError.selector
        );
        _pendingApprovalRequestIds[owner][spender] = requestId;
        emit ApprovalRequestSubmitted(owner, spender, requestId);
    }

    function _burn(
        address from,
        itUint256 calldata value
    ) internal returns (bytes32 requestId) {
        if (_pendingTransferRequstIds[from] != bytes32(0)) {
            revert TransferAlreadyPending(from, address(0), _pendingTransferRequstIds[from]);
        }

        IInbox.MpcMethodCall memory mpcMethodCall =
            MpcAbiCodec.create(IPodErc20CotiSide.burn.selector, 2)
            .addArgument(from)
            .addArgument(value)
            .build();

        requestId = IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            cotiSideContract,
            mpcMethodCall,
            PodERC20.transferCallback.selector,
            PodERC20.transferError.selector
        );

        _pendingTransferRequstIds[from] = requestId;
        emit TransferRequestSubmitted(from, address(0), requestId);
    }
    
    function _transfer(
        bytes4 remoteTransferSelector,
        address from,
        address to,
        itUint256 calldata value
    ) internal returns (bytes32 requestId) {
        if (_pendingTransferRequstIds[from] != bytes32(0) || _pendingTransferRequstIds[to] != bytes32(0)) {
            revert TransferAlreadyPending(from, to, _pendingTransferRequstIds[from]);
        }

        IInbox.MpcMethodCall memory mpcMethodCall =
            MpcAbiCodec.create(remoteTransferSelector, 3)
            .addArgument(from)
            .addArgument(to)
            .addArgument(value)
            .build();

        requestId = IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            cotiSideContract,
            mpcMethodCall,
            PodERC20.transferCallback.selector,
            PodERC20.transferError.selector
        );
        _pendingTransferRequstIds[from] = requestId;
        _pendingTransferRequstIds[to] = requestId;
        emit TransferRequestSubmitted(msg.sender, to, requestId);
    }

    function transferCallback(bytes memory data) external onlyInbox {
        // We only accept remote calls from the coti side contract
        (uint256 remoteChainId, address remoteContract) = inbox.inboxMsgSender();
        if (remoteChainId != cotiChainId || remoteContract != cotiSideContract) {
            revert OnlyCotiSideContract(remoteChainId, remoteContract);
        }
        bytes32 sourceRequestId = inbox.inboxSourceRequestId();
        (address from, ctUint256 memory newBalanceFrom, ctUint256 memory senderValue,
        address to, ctUint256 memory newBalanceTo, ctUint256 memory receiverValue) = abi.decode(data, (address, ctUint256, ctUint256, address, ctUint256, ctUint256));
        if (from != address(0)) {
            _pendingTransferRequstIds[from] = bytes32(0);
            _balances[from] = newBalanceFrom;
        }
        if (to != address(0)) {
            _pendingTransferRequstIds[to] = bytes32(0);
            _balances[to] = newBalanceTo;
        }
        bytes memory callbackData = _requestCallbacks[sourceRequestId];
        if (callbackData.length != 0) {
            (bool success, ) = address(to).call(callbackData);
            if (!success) {
                emit RequestCallbackFailed(from, to, sourceRequestId, callbackData);
            }
            delete _requestCallbacks[sourceRequestId];
        }
        emit Transfer(from, to, senderValue, receiverValue);
    }

    function transferError(bytes memory data) external onlyInbox {
        // We only accept remote calls from the coti side contract
        (uint256 remoteChainId, address remoteContract) = inbox.inboxMsgSender();
        if (remoteChainId != cotiChainId || remoteContract != cotiSideContract) {
            revert OnlyCotiSideContract(remoteChainId, remoteContract);
        }
        (address from, address to, bytes memory errorMsg) = abi.decode(data, (address, address, bytes));
        bytes32 sourceRequestId = inbox.inboxSourceRequestId();
        failedRequests[sourceRequestId] = errorMsg;
        if (from != address(0)) {
            _pendingTransferRequstIds[from] = bytes32(0);
        }
        _pendingTransferRequstIds[to] = bytes32(0);
        emit TransferFailed(from, to, errorMsg);
    }

    function approveCallback(bytes memory data) external onlyInbox {
        // We only accept remote calls from the coti side contract
        (uint256 remoteChainId, address remoteContract) = inbox.inboxMsgSender();
        if (remoteChainId != cotiChainId || remoteContract != cotiSideContract) {
            revert OnlyCotiSideContract(remoteChainId, remoteContract);
        }
        (address owner, ctUint256 memory ownerAmount,
        address spender, ctUint256 memory spenderAmount) = abi.decode(data, (address, ctUint256, address, ctUint256));
        _pendingApprovalRequestIds[owner][spender] = bytes32(0);
        _allowance[owner][spender] = Allowance({
            spenderCiphertext: spenderAmount,
            ownerCiphertext: ownerAmount
        });
        emit Approval(owner, spender, ownerAmount, spenderAmount);
    }

    function approveError(bytes memory data) external onlyInbox {
        // We only accept remote calls from the coti side contract
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

    function syncBalancesCallback(bytes memory data) external onlyInbox {
        // We only accept remote calls from the coti side contract
        (uint256 remoteChainId, address remoteContract) = inbox.inboxMsgSender();
        if (remoteChainId != cotiChainId || remoteContract != cotiSideContract) {
            revert OnlyCotiSideContract(remoteChainId, remoteContract);
        }
        (address[] memory addresses, ctUint256[] memory amounts) = abi.decode(data, (address[], ctUint256[]));
        for (uint256 i = 0; i < addresses.length; i++) {
            _balances[addresses[i]] = amounts[i];
            emit BalanceSynced(addresses[i], amounts[i]);
        }
    }

    function syncBalancesError(bytes memory data) external onlyInbox {
        // We only accept remote calls from the coti side contract
        (uint256 remoteChainId, address remoteContract) = inbox.inboxMsgSender();
        if (remoteChainId != cotiChainId || remoteContract != cotiSideContract) {
            revert OnlyCotiSideContract(remoteChainId, remoteContract);
        }
        bytes32 sourceRequestId = inbox.inboxSourceRequestId();
        emit SyncBalancesFailed(sourceRequestId, data);
    }
}