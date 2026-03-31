// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../IInbox.sol";
import "../../mpccodec/MpcAbiCodec.sol";
import { PodLib } from "../../mpc/PodLib.sol";
import { PodLibBase } from "../../mpc/PodLibBase.sol";

/// @title Millionaire
/// @notice Example MPC “millionaire” comparison using {PodLib} and the inbox.
contract Millionaire is PodLib {
    event RevealResult(bytes32 indexed requestId, ctBool result);

    constructor(address _inbox) PodLibBase(msg.sender) {
        setInbox(_inbox);
    }

    mapping(address => itUint64) internal encryptedWealthOf;
    mapping(address => mapping(address => bytes32)) internal revealRequests;
    mapping(bytes32 => ctBool) public revealResults;

    function isWealthRegistered(address account) public view returns (bool) {
        return encryptedWealthOf[account].signature.length != 0;
    }

    function registerMyWealth(itUint64 memory wealth) external {
        encryptedWealthOf[msg.sender] = wealth;
    }

    /// @param callbackFeeLocalWei Wei slice for each comparison's callback leg; `msg.value` is split evenly across the two inbox sends.
    function reveal(address a, address b, uint256 callbackFeeLocalWei) external payable {
        require(isWealthRegistered(a), "A's wealth is not registered");
        require(isWealthRegistered(b), "B's wealth is not registered");
        uint256 half = msg.value / 2;
        uint256 rest = msg.value - half;
        require(callbackFeeLocalWei <= half && callbackFeeLocalWei <= rest, "Millionaire: callback fee");
        itUint64 memory wealthA = encryptedWealthOf[a];
        itUint64 memory wealthB = encryptedWealthOf[b];
        revealRequests[a][b] = gt64(
            wealthA,
            wealthB,
            a,
            this.revealCallback.selector,
            PodLibBase.onDefaultMpcError.selector,
            half,
            callbackFeeLocalWei
        );
        revealRequests[b][a] = gt64(
            wealthB,
            wealthA,
            b,
            this.revealCallback.selector,
            PodLibBase.onDefaultMpcError.selector,
            rest,
            callbackFeeLocalWei
        );
    }

    function revealMyWealthGtThan(address b) external view returns (bool,ctBool) {
        return revealWealthComparison(msg.sender, b);
    }

    function revealCallback(bytes memory data) external onlyInbox {
        bytes32 requestId = inbox.inboxSourceRequestId();
        if (requestId == bytes32(0)) {
            requestId = inbox.inboxRequestId();
        }
        ctBool result = abi.decode(data, (ctBool));
        revealResults[requestId] = result;
        emit RevealResult(requestId, result);
    }

    function revealWealthComparison(address a,address b) public view returns (bool,ctBool) {
        bytes32 requestId = revealRequests[a][b];
        if (requestId == 0) {
            return (false, ctBool.wrap(0));
        }
        return (true, revealResults[requestId]);
    }
}