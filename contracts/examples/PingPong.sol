// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../InboxUser.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Ping is InboxUser {
    uint peerChainId;
    address peerContract;

    event PingReceived(string message, uint fromChainId);
    event PingAck(bytes32 requestId, uint remoteChainId);
    event ErrorRemoteCall(bytes32 requestId, uint code, string message);

    constructor(address _inbox) Ownable(msg.sender) {
        setInbox(_inbox);
    }

    function setPeerContract(address _peerContract, uint _peerChainId) external onlyOwner {    
        peerContract = _peerContract;
        peerChainId = _peerChainId;
    }

    function ping(string memory message) external {
        bytes memory encodedMessage = abi.encodeWithSelector(Ping.remotePing.selector, message);
        inbox.sendTwoWayMessage(
            peerChainId,
            peerContract,
            encodedMessage,
            Ping.pingCallBack.selector,
            Ping.onError.selector);
    }

    function pingCallBack(bytes32 requestId) external onlyInbox {
        bytes memory responseData = inbox.getInboxResponse(requestId);
        // We must know how the callback data looks like, as we design it
        (uint remoteChainId) = abi.decode(responseData, (uint));
        emit PingAck(requestId, remoteChainId);
    }

    function onError(bytes32 requestId) external onlyInbox {
        (uint code, string memory message) = inbox.getOutboxError(requestId);
        emit ErrorRemoteCall(requestId, code, message);
    }

    function remotePing(string memory message) external onlyInbox {
        (uint callerChainId, address callerContract) = inbox.inboxMsgSender();
        require(callerChainId == peerChainId, "Only peer chain");
        require(callerContract == peerContract, "Only peer contract");

        emit PingReceived(message, callerChainId);
        inbox.respond(abi.encode(block.chainid)); // Send the ack message
    }
}