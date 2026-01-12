// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract Inbox {
    struct Message {
        uint256 chainId;
        uint256 reqId;
        address sender;
        uint256 timestamp;
        bool processed;
    }

    uint256 public immutable chainId;
    mapping(bytes32 => Message) public messages;
    bytes32[] public messageHashes;
    
    event MessageSent(
        bytes32 indexed messageHash,
        uint256 indexed chainId,
        uint256 indexed reqId,
        address sender,
        uint256 timestamp
    );
    
    event MessageReceived(
        bytes32 indexed messageHash,
        uint256 indexed chainId,
        uint256 indexed reqId,
        address sender
    );

    constructor(uint256 _chainId) {
        require(_chainId != 0, "Inbox: chainId cannot be zero");
        chainId = _chainId;
    }

    function sendMessage(uint256 targetChainId, uint256 reqId) external returns (bytes32) {
        require(targetChainId != 0, "Inbox: targetChainId cannot be zero");
        require(targetChainId != chainId, "Inbox: cannot send to same chain");
        
        bytes32 messageHash = keccak256(
            abi.encodePacked(chainId, targetChainId, reqId, msg.sender, block.timestamp)
        );
        
        messages[messageHash] = Message({
            chainId: targetChainId,
            reqId: reqId,
            sender: msg.sender,
            timestamp: block.timestamp,
            processed: false
        });
        
        messageHashes.push(messageHash);
        emit MessageSent(messageHash, targetChainId, reqId, msg.sender, block.timestamp);
        return messageHash;
    }

    function receiveMessage(
        uint256 sourceChainId,
        uint256 reqId,
        address sender,
        uint256 timestamp,
        bytes32 messageHash
    ) external returns (bool) {
        require(sourceChainId != 0, "Inbox: sourceChainId cannot be zero");
        require(sourceChainId != chainId, "Inbox: cannot receive from same chain");
        require(sender != address(0), "Inbox: sender cannot be zero address");
        
        bytes32 expectedHash = keccak256(
            abi.encodePacked(sourceChainId, chainId, reqId, sender, timestamp)
        );
        require(expectedHash == messageHash, "Inbox: invalid message hash");
        require(!messages[messageHash].processed, "Inbox: message already processed");
        
        messages[messageHash] = Message({
            chainId: sourceChainId,
            reqId: reqId,
            sender: sender,
            timestamp: timestamp,
            processed: true
        });
        
        messageHashes.push(messageHash);
        emit MessageReceived(messageHash, sourceChainId, reqId, sender);
        return true;
    }

    function getMessageCount() external view returns (uint256) {
        return messageHashes.length;
    }

    function getMessage(bytes32 messageHash) external view returns (Message memory) {
        return messages[messageHash];
    }
}
