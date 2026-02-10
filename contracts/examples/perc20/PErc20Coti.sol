// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../../InboxUser.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

contract PErc20Coti is InboxUser {
    uint64 TOTAL_SUPPLY = 1_000_000;

    /// @notice Create the example COTI-side privacy ERC20 contract.
    /// @param _inbox The inbox contract address.
    constructor(address _inbox) {
        setInbox(_inbox);
        gtUint64 toMint = MpcCore.setPublic64(TOTAL_SUPPLY);
        balanceOf[keccak256(abi.encode(msg.sender))] = MpcCore.offBoard(toMint);
    }

    mapping(bytes32 => ctUint64) public balanceOf;

    function transferFrom(address from, gtUint256 calldata to, gtUint64 amount
    ) external onlyInbox {
        // Get the balance of for from and to
        // reduce or revert
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