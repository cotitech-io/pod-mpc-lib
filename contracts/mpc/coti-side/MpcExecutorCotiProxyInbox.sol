// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/**
 * @title MpcExecutorCotiProxyInbox
 * @notice Minimal inbox stub for `MpcExecutor`: only stores `respond` payload bytes. The harness decodes + decrypts.
 */
contract MpcExecutorCotiProxyInbox {
    address public executor;

    bytes public lastRespondData;

    error AlreadySet();
    error OnlyExecutor();

    function registerExecutor(address e) external {
        if (executor != address(0)) revert AlreadySet();
        executor = e;
    }

    function respond(bytes memory data) external {
        if (msg.sender != executor) revert OnlyExecutor();
        lastRespondData = data;
    }
}
