// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./MpcExecutor.sol";

/**
 * @title MpcExecutorCotiProxyInbox
 * @notice Minimal inbox stub for `MpcExecutor`: stores `respond` payload bytes and forwards `mul*FromPlain` so
 *         `onlyInbox` passes and `setPublic*` + `mul` run inside `MpcExecutor` (COTI MPC precompile requirement).
 */
contract MpcExecutorCotiProxyInbox {
    address public executor;

    bytes public lastRespondData;

    error AlreadySet();
    error OnlyExecutor();
    error ExecutorNotSet();

    function registerExecutor(address e) external {
        if (executor != address(0)) revert AlreadySet();
        executor = e;
    }

    function respond(bytes memory data) external {
        if (msg.sender != executor) revert OnlyExecutor();
        lastRespondData = data;
    }

    function forwardMul256FromPlain(uint256 a, uint256 b, address cOwner) external {
        if (executor == address(0)) revert ExecutorNotSet();
        MpcExecutor(executor).mul256FromPlain(a, b, cOwner);
    }

    function forwardMul128FromPlain(uint128 a, uint128 b, address cOwner) external {
        if (executor == address(0)) revert ExecutorNotSet();
        MpcExecutor(executor).mul128FromPlain(a, b, cOwner);
    }

    function forwardMul64FromPlain(uint64 a, uint64 b, address cOwner) external {
        if (executor == address(0)) revert ExecutorNotSet();
        MpcExecutor(executor).mul64FromPlain(a, b, cOwner);
    }
}
