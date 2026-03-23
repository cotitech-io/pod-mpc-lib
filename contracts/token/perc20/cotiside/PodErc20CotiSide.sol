// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../../InboxUser.sol";
import "./IPodErc20CotiSide.sol";

/**
 * @title PodErc20CotiSide
 * @notice COTI-side ledger for {PodERC20}: balances and allowances live in MPC “garbled” form (`gtUint256`).
 *         Successful operations call {IInbox.respond} with payloads shaped for `PodERC20` callbacks.
 *         Failures call {IInbox.raise} so the remote `errorSelector` runs with the same `sourceRequestId` linkage as success.
 * @dev Only the inbox may call this contract, and only for messages whose sender matches {authorizedRemoteChainId}
 *      and {authorizedRemoteContract} (the remote `PodERC20`). Owner must set that pair after deploy.
 * @dev `transferFrom` uses the same 3 arguments as `transfer` on the wire (no spender here); enforce allowance on `PodERC20` before sending.
 *      Ciphertext (`ctUint256`) is produced only when building responses for the PoD chain, not stored on COTI.
 */
contract PodErc20CotiSide is IPodErc20CotiSide, InboxUser, Ownable {
    /// @notice Chain ID where the trusted `PodERC20` lives (must equal {IInbox.inboxMsgSender}’s chain).
    uint256 public authorizedRemoteChainId;
    /// @notice Address of that `PodERC20` on the remote chain.
    address public authorizedRemoteContract;

    error TrustedRemoteNotConfigured();
    error InvalidAuthorizedRemotePeer();
    error UntrustedRemoteCaller(uint256 chainId, address remoteContract);
    error MintToZeroAddress();

    event AuthorizedRemoteUpdated(uint256 indexed chainId, address indexed remoteContract);

    /// @dev Garbled (secret-shared) balance per account; empty storage means “never written”, not necessarily numeric zero.
    mapping(address => gtUint256) private _garbledBalances;
    /// @dev Garbled allowance: owner => spender => amount.
    mapping(address => mapping(address => gtUint256)) private _garbledAllowances;

    constructor(address inboxAddress, address initialOwner) Ownable(initialOwner) {
        setInbox(inboxAddress);
    }

    /// @notice Restrict inbox calls to the configured remote `PodERC20` (chain + contract).
    function setAuthorizedRemote(uint256 chainId, address remotePodToken) external onlyOwner {
        if (chainId == 0 || remotePodToken == address(0)) {
            revert InvalidAuthorizedRemotePeer();
        }
        authorizedRemoteChainId = chainId;
        authorizedRemoteContract = remotePodToken;
        emit AuthorizedRemoteUpdated(chainId, remotePodToken);
    }

    /// @notice Owner-only: mint plain `amount` to `to` on the COTI garbled ledger (e.g. bridge or test setup
    ///         before {PodERC20.syncBalances} pulls ciphertext to the PoD chain).
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert MintToZeroAddress();
        }
        gtUint256 memory addend = MpcCore.setPublic256(amount);
        gtUint256 memory cur = _readGarbledBalance(to);
        _writeGarbledBalance(to, MpcCore.add(cur, addend));
    }

    /// @dev Caller must be the inbox, and the active cross-chain message must be from the authorized `PodERC20`.
    modifier onlyAuthorizedPodTokenMessage() {
        if (msg.sender != address(inbox)) {
            revert OnlyInbox(msg.sender);
        }
        if (authorizedRemoteChainId == 0 || authorizedRemoteContract == address(0)) {
            revert TrustedRemoteNotConfigured();
        }
        (uint256 messageChainId, address messageContract) = inbox.inboxMsgSender();
        if (messageChainId != authorizedRemoteChainId || messageContract != authorizedRemoteContract) {
            revert UntrustedRemoteCaller(messageChainId, messageContract);
        }
        _;
    }

    /// @inheritdoc IPodErc20CotiSide
    function syncBalances(address[] calldata accounts) external override onlyAuthorizedPodTokenMessage {
        if (accounts.length == 0) {
            _sendSyncFailureToPod(bytes("PodErc20CotiSide: empty accounts"));
            return;
        }

        uint256 count = accounts.length;
        address[] memory addresses = new address[](count);
        ctUint256[] memory ciphertextAmounts = new ctUint256[](count);

        for (uint256 i = 0; i < count; ++i) {
            address account = accounts[i];
            addresses[i] = account;
            gtUint256 memory garbledBalance = _readGarbledBalance(account);
            ciphertextAmounts[i] = MpcCore.offBoardToUser(garbledBalance, account);
        }

        inbox.respond(abi.encode(addresses, ciphertextAmounts));
    }

    /// @inheritdoc IPodErc20CotiSide
    function transfer(address from, address to, gtUint256 calldata value) external override onlyAuthorizedPodTokenMessage {
        _moveOrBurn(from, to, _garbledFromCalldata(value), false);
    }

    /// @inheritdoc IPodErc20CotiSide
    function transferFrom(address from, address to, gtUint256 calldata value) external override onlyAuthorizedPodTokenMessage {
        // Spender is not in the cross-chain calldata; `PodERC20` must check allowance before sending.
        _moveOrBurn(from, to, _garbledFromCalldata(value), false);
    }

    /// @inheritdoc IPodErc20CotiSide
    function approve(address owner, address spender, gtUint256 calldata value) external override onlyAuthorizedPodTokenMessage {
        if (owner == address(0) || spender == address(0)) {
            _sendApproveFailureToPod(owner, spender, bytes("PodErc20CotiSide: zero owner or spender"));
            return;
        }

        gtUint256 memory garbledAllowance = _garbledFromCalldata(value);
        _garbledAllowances[owner][spender] = garbledAllowance;

        ctUint256 memory ciphertextForOwner = MpcCore.offBoardToUser(garbledAllowance, owner);
        ctUint256 memory ciphertextForSpender = MpcCore.offBoardToUser(garbledAllowance, spender);
        inbox.respond(abi.encode(owner, ciphertextForOwner, spender, ciphertextForSpender));
    }

    /// @inheritdoc IPodErc20CotiSide
    function burn(address from, gtUint256 calldata value) external override onlyAuthorizedPodTokenMessage {
        _moveOrBurn(from, address(0), _garbledFromCalldata(value), true);
    }

    // --- Internal: garbled balance helpers ---

    /// @dev Copy `gtUint256` from calldata into memory for `MpcCore` APIs.
    function _garbledFromCalldata(gtUint256 calldata value) private pure returns (gtUint256 memory garbled) {
        garbled = value;
    }

    /// @dev Plain zero as ciphertext (for burn “to” side in the callback tuple).
    function _ciphertextPlainZero() private returns (ctUint256 memory) {
        return MpcCore.offBoard(MpcCore.setPublic256(0));
    }

    /// @dev Fresh storage reads as an all-zero struct; that is not the same as garbled zero, so we treat it as “no row yet”.
    function _looksLikeFreshStorage(gtUint256 memory maybeEmpty) private pure returns (bool) {
        return gtUint64.unwrap(maybeEmpty.high.high) == 0 && gtUint64.unwrap(maybeEmpty.high.low) == 0
            && gtUint64.unwrap(maybeEmpty.low.high) == 0 && gtUint64.unwrap(maybeEmpty.low.low) == 0;
    }

    function _readGarbledBalance(address account) private returns (gtUint256 memory) {
        gtUint256 memory stored = _garbledBalances[account];
        if (_looksLikeFreshStorage(stored)) {
            return MpcCore.setPublic256(0);
        }
        return stored;
    }

    function _writeGarbledBalance(address account, gtUint256 memory newBalance) private {
        _garbledBalances[account] = newBalance;
    }

    function _moveOrBurn(address from, address to, gtUint256 memory amount, bool burning) private {
        if (from == address(0)) {
            _sendTransferFailureToPod(from, to, bytes("PodErc20CotiSide: zero from"));
            return;
        }
        if (!burning && to == address(0)) {
            _sendTransferFailureToPod(from, to, bytes("PodErc20CotiSide: zero to"));
            return;
        }

        gtUint256 memory senderBalance = _readGarbledBalance(from);

        if (!MpcCore.decrypt(MpcCore.ge(senderBalance, amount))) {
            _sendTransferFailureToPod(from, to, bytes("PodErc20CotiSide: insufficient balance"));
            return;
        }

        gtUint256 memory senderAfter = MpcCore.sub(senderBalance, amount);
        _writeGarbledBalance(from, senderAfter);

        if (burning) {
            ctUint256 memory zeroCiphertext = _ciphertextPlainZero();
            inbox.respond(
                abi.encode(
                    from,
                    MpcCore.offBoard(senderAfter),
                    MpcCore.offBoardToUser(amount, from),
                    address(0),
                    zeroCiphertext,
                    zeroCiphertext
                )
            );
            return;
        }

        gtUint256 memory recipientBefore = _readGarbledBalance(to);
        gtUint256 memory recipientAfter = MpcCore.add(recipientBefore, amount);
        _writeGarbledBalance(to, recipientAfter);

        inbox.respond(_encodePodTransferCallback(from, to, amount, senderAfter, recipientAfter));
    }

    function _encodePodTransferCallback(
        address from,
        address to,
        gtUint256 memory amount,
        gtUint256 memory senderBalanceAfter,
        gtUint256 memory recipientBalanceAfter
    ) private returns (bytes memory) {
        ctUint256 memory senderBalanceCt = MpcCore.offBoard(senderBalanceAfter);
        ctUint256 memory amountForSender = MpcCore.offBoardToUser(amount, from);
        ctUint256 memory recipientBalanceCt = MpcCore.offBoard(recipientBalanceAfter);
        ctUint256 memory amountForRecipient = MpcCore.offBoardToUser(amount, to);
        return abi.encode(from, senderBalanceCt, amountForSender, to, recipientBalanceCt, amountForRecipient);
    }

    function _sendTransferFailureToPod(address from, address to, bytes memory reason) private {
        inbox.raise(abi.encode(from, to, reason));
    }

    function _sendApproveFailureToPod(address owner, address spender, bytes memory reason) private {
        inbox.raise(abi.encode(owner, spender, reason));
    }

    function _sendSyncFailureToPod(bytes memory reason) private {
        inbox.raise(reason);
    }
}
