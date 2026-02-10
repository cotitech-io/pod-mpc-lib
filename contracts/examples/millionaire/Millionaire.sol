// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { MpcLib } from "../../mpc/MpcLib.sol";
import "../../mpccodec/MpcAbiCodec.sol";
import "../../IInbox.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

contract Millionaire is MpcLib {
    event RevealResult(bytes32 indexed requestId, ctBool result);

    constructor(address _inbox) {
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

    function reveal(address a, address b) external {
        require(isWealthRegistered(a), "A's wealth is not registered");
        require(isWealthRegistered(b), "B's wealth is not registered");
        itUint64 memory wealthA = encryptedWealthOf[a];
        itUint64 memory wealthB = encryptedWealthOf[b];
        revealRequests[a][b] = gt(
            wealthA,
            wealthB,
            a,
            this.revealCallback.selector,
            this.onDefaultMpcError.selector);
        revealRequests[b][a] = gt(
            wealthB,
            wealthA,
            b,
            this.revealCallback.selector,
            this.onDefaultMpcError.selector);
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