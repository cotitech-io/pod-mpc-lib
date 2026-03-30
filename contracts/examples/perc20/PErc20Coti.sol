// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../InboxUser.sol";

/// @title PErc20Coti
/// @notice COTI-side ledger for {PErc20}: `ctUint64` balances by `keccak256(abi.encode(account))`.
/// @dev Recipient address is derived in plaintext for routing—privacy is limited. Constructor mints to deployer hash only.
contract PErc20Coti is InboxUser {
    uint64 private constant TOTAL_SUPPLY = 1_000_000;

    mapping(bytes32 => ctUint64) public balanceOf;

    /// @param _inbox Inbox address for {InboxUser.setInbox}. Seeds deployer balance with `TOTAL_SUPPLY` in garbled form.
    constructor(address _inbox) {
        setInbox(_inbox);
        gtUint64 toMint = MpcCore.setPublic64(TOTAL_SUPPLY);
        balanceOf[keccak256(abi.encode(msg.sender))] = MpcCore.offBoard(toMint);
    }

    /**
     * @notice Inbox-only: subtracts `amount` from `from`’s bucket and credits the recipient implied by encrypted `to`.
     * @dev **Gotcha:** treats all-zero `ctUint64` as “uninitialized” and substitutes off-boarded zero—same pattern as larger PoD tokens
     *      but still heuristic. **Gotcha:** no overflow checks beyond MPC `sub`/`add` behavior.
     */
    function transferFrom(address from, gtUint256 calldata to, gtUint64 amount) external onlyInbox {
        bytes32 fromHash = keccak256(abi.encode(from));
        address toAddr = address(uint160(uint256(MpcCore.decrypt(to))));
        bytes32 toHash = keccak256(abi.encode(toAddr));

        ctUint64 fromCipher = balanceOf[fromHash];
        if (ctUint64.unwrap(fromCipher) == 0) {
            fromCipher = MpcCore.offBoard(MpcCore.setPublic64(0));
        }
        ctUint64 toCipher = balanceOf[toHash];
        if (ctUint64.unwrap(toCipher) == 0) {
            toCipher = MpcCore.offBoard(MpcCore.setPublic64(0));
        }

        gtUint64 fromBalance = MpcCore.onBoard(fromCipher);
        gtUint64 toBalance = MpcCore.onBoard(toCipher);

        gtUint64 newFromBalance = MpcCore.sub(fromBalance, amount);
        gtUint64 newToBalance = MpcCore.add(toBalance, amount);

        balanceOf[fromHash] = MpcCore.offBoard(newFromBalance);
        balanceOf[toHash] = MpcCore.offBoard(newToBalance);

        ctUint64 fromBalanceResponse = MpcCore.offBoardToUser(newFromBalance, from);
        ctUint64 toBalanceResponse = MpcCore.offBoardToUser(newToBalance, toAddr);

        inbox.respond(abi.encode(fromHash, fromBalanceResponse, toHash, toBalanceResponse));
    }
}
