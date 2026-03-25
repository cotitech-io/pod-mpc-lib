// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../../InboxUser.sol";
import "./IPodErc20CotiSide.sol";


/**
 * @title PodErc20CotiSide
 * @notice COTI-side ledger for {PodERC20}: balances and allowances are stored as `ctUint256` (off-boarded ciphertext), matching the
 *         pattern in {PErc20Coti}. Garbled values (`gtUint256`) exist only in memory: `onBoard`/`offBoard` bridge storage and MPC ops.
 * @dev Only the inbox may call operational entry points, and only for messages from {authorizedRemoteChainId} + {authorizedRemoteContract}.
 *      The owner must call {setAuthorizedRemote} after deploy. All-zero `ctUint256` slots are treated as uninitialized (see {_readGarbledBalance}).
 */
contract PodErc20CotiSide is IPodErc20CotiSide, InboxUser, Ownable {
    // --- State variables ---

    /// @notice Chain ID where the trusted `PodERC20` lives (must match {IInbox.inboxMsgSender}’s chain).
    uint256 public authorizedRemoteChainId;
    /// @notice Address of that `PodERC20` on the remote chain.
    address public authorizedRemoteContract;
    /// @notice Increments on successful state-changing MPC paths; included in PoD callbacks for ordering.
    uint256 public nonce;
    /// @dev Balance ciphertext per account (`offBoard` of garbled balance), same design as {PErc20Coti}.
    mapping(address => ctUint256) private _balanceCiphertext;
    /// @dev Allowance ciphertext: `owner => spender => ctUint256`.
    mapping(address => mapping(address => ctUint256)) private _allowanceCiphertext;

    // --- Events ---

    event AuthorizedRemoteUpdated(uint256 indexed chainId, address indexed remoteContract);

    // --- Errors ---

    error TrustedRemoteNotConfigured();
    error InvalidAuthorizedRemotePeer();
    error UntrustedRemoteCaller(uint256 chainId, address remoteContract);
    error MintToZeroAddress();

    // --- Modifiers ---

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

    // --- Constructor ---

    constructor(address inboxAddress, address initialOwner) Ownable(initialOwner) {
        setInbox(inboxAddress);
    }

    // --- External: owner ---

    /**
     * @notice Configures which remote `PodERC20` may drive this contract through the inbox.
     * @dev Reverts if `chainId` or `remotePodToken` is zero.
     */
    function setAuthorizedRemote(uint256 chainId, address remotePodToken) external onlyOwner {
        if (chainId == 0 || remotePodToken == address(0)) {
            revert InvalidAuthorizedRemotePeer();
        }
        authorizedRemoteChainId = chainId;
        authorizedRemoteContract = remotePodToken;
        emit AuthorizedRemoteUpdated(chainId, remotePodToken);
    }

    /**
     * @inheritdoc IPodErc20CotiSide
     * @dev Increments {nonce} after mint. **Gotcha:** does not increase ERC-20 `totalSupply` on PoD—supply is a deployment concern.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert MintToZeroAddress();
        }
        ctUint256 memory ct = _balanceCiphertext[to];
        if (_isEmptyCtUint256(ct)) {
            _balanceCiphertext[to] = MpcCore.offBoard(MpcCore.setPublic256(amount));
        } else {
            gtUint256 memory cur = MpcCore.onBoard(ct);
            _balanceCiphertext[to] = MpcCore.offBoard(MpcCore.add(cur, MpcCore.setPublic256(amount)));
        }
        nonce++;
    }

    // --- External: inbox + authorized remote ---

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

        inbox.respond(abi.encode(addresses, ciphertextAmounts, nonce));
        nonce++;
    }

    /// @inheritdoc IPodErc20CotiSide
    function transfer(address from, address to, gtUint256 calldata value) external override onlyAuthorizedPodTokenMessage {
        _moveOrBurn(from, to, _garbledFromCalldata(value), false);
    }

    /// @inheritdoc IPodErc20CotiSide
    function transferFrom(
        address from,
        address to,
        gtUint256 calldata value
    ) external override onlyAuthorizedPodTokenMessage {
        _moveOrBurn(from, to, _garbledFromCalldata(value), false);
    }

    /// @inheritdoc IPodErc20CotiSide
    function approve(
        address owner,
        address spender,
        gtUint256 calldata value
    ) external override onlyAuthorizedPodTokenMessage {
        if (owner == address(0) || spender == address(0)) {
            _sendApproveFailureToPod(owner, spender, bytes("PodErc20CotiSide: zero owner or spender"));
            return;
        }

        gtUint256 memory garbledAllowance = _garbledFromCalldata(value);
        _allowanceCiphertext[owner][spender] = MpcCore.offBoard(garbledAllowance);

        ctUint256 memory ciphertextForOwner = MpcCore.offBoardToUser(garbledAllowance, owner);
        ctUint256 memory ciphertextForSpender = MpcCore.offBoardToUser(garbledAllowance, spender);
        inbox.respond(abi.encode(owner, ciphertextForOwner, spender, ciphertextForSpender));
    }

    /// @inheritdoc IPodErc20CotiSide
    function burn(address from, gtUint256 calldata value) external override onlyAuthorizedPodTokenMessage {
        _moveOrBurn(from, address(0), _garbledFromCalldata(value), true);
    }

    // --- Private: garbled balance helpers ---

    /// @dev Copies `gtUint256` from calldata into memory for `MpcCore` APIs.
    function _garbledFromCalldata(gtUint256 calldata value) private pure returns (gtUint256 memory garbled) {
        garbled = value;
    }

    /// @dev Plain zero as ciphertext (for burn “to” side in the callback tuple and empty-balance `onBoard` input).
    function _ciphertextPlainZero() private returns (ctUint256 memory) {
        return MpcCore.offBoard(MpcCore.setPublic256(0));
    }

    /// @dev All ciphertext limbs zero → treat slot as uninitialized (same idea as {PErc20Coti} `ctUint64.unwrap == 0`).
    function _isEmptyCtUint256(ctUint256 memory ct) private pure returns (bool) {
        return ctUint64.unwrap(ct.high.high) == 0 && ctUint64.unwrap(ct.high.low) == 0
            && ctUint64.unwrap(ct.low.high) == 0 && ctUint64.unwrap(ct.low.low) == 0;
    }

    function _readGarbledBalance(address account) private returns (gtUint256 memory) {
        ctUint256 memory ct = _balanceCiphertext[account];
        if (_isEmptyCtUint256(ct)) {
            return MpcCore.onBoard(_ciphertextPlainZero());
        }
        return MpcCore.onBoard(ct);
    }

    function _writeGarbledBalance(address account, gtUint256 memory newBalance) private {
        _balanceCiphertext[account] = MpcCore.offBoard(newBalance);
    }

    /**
     * @dev Validates addresses, checks `ge(balance, amount)` via decrypt, updates storage, then `respond` or `raise`.
     * @dev **Gotcha:** insufficient balance uses `raise` (PoD sees `transferError`), not a revert.
     */
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
                    MpcCore.offBoardToUser(senderAfter, from),
                    MpcCore.offBoardToUser(amount, from),
                    address(0),
                    zeroCiphertext,
                    zeroCiphertext,
                    nonce
                )
            );
            nonce++;
            return;
        }

        gtUint256 memory recipientBefore = _readGarbledBalance(to);
        gtUint256 memory recipientAfter = MpcCore.add(recipientBefore, amount);
        _writeGarbledBalance(to, recipientAfter);

        inbox.respond(_encodePodTransferCallback(from, to, amount, senderAfter, recipientAfter, nonce));
        nonce++;
    }

    function _encodePodTransferCallback(
        address from,
        address to,
        gtUint256 memory amount,
        gtUint256 memory senderBalanceAfter,
        gtUint256 memory recipientBalanceAfter,
        uint256 callbackNonce
    ) private returns (bytes memory) {
        ctUint256 memory senderBalanceCt = MpcCore.offBoardToUser(senderBalanceAfter, from);
        ctUint256 memory amountForSender = MpcCore.offBoardToUser(amount, from);
        ctUint256 memory recipientBalanceCt = MpcCore.offBoardToUser(recipientBalanceAfter, to);
        ctUint256 memory amountForRecipient = MpcCore.offBoardToUser(amount, to);
        return abi.encode(from, senderBalanceCt, amountForSender, to, recipientBalanceCt, amountForRecipient, callbackNonce);
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
