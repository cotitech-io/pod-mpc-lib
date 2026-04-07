// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./MpcExecutor.sol";

/// @title MpcExecutorCotiProxyInbox
/// @notice Minimal inbox stub for COTI tests: records `respond` data and forwards `mul*FromPlain` into {MpcExecutor} so `onlyInbox` passes.
/// @dev Lets `setPublic*` and `mul` run inside the executor contract (COTI MPC precompile requirement).
contract MpcExecutorCotiProxyInbox {
    address public executor;

    bytes public lastRespondData;

    error AlreadySet();
    error ExecutorNotSet();
    error OnlyExecutor();

    /// @notice One-time link of the deployed {MpcExecutor}.
    /// @param e Executor address.
    function registerExecutor(address e) external {
        if (executor != address(0)) revert AlreadySet();
        executor = e;
    }

    /// @notice Records the last `respond` payload from the executor (test harness).
    /// @param data Opaque response bytes.
    function respond(bytes memory data) external {
        if (msg.sender != executor) revert OnlyExecutor();
        lastRespondData = data;
    }

    /// @notice Forward `mul64FromPlain` to the executor.
    function forwardMul64FromPlain(uint64 a, uint64 b, address cOwner) external {
        if (executor == address(0)) revert ExecutorNotSet();
        MpcExecutor(executor).mul64FromPlain(a, b, cOwner);
    }

    /// @notice Forward `mul128FromPlain` to the executor.
    function forwardMul128FromPlain(uint128 a, uint128 b, address cOwner) external {
        if (executor == address(0)) revert ExecutorNotSet();
        MpcExecutor(executor).mul128FromPlain(a, b, cOwner);
    }

    /// @notice Forward `mul256FromPlain` to the executor.
    function forwardMul256FromPlain(uint256 a, uint256 b, address cOwner) external {
        if (executor == address(0)) revert ExecutorNotSet();
        MpcExecutor(executor).mul256FromPlain(a, b, cOwner);
    }
}
