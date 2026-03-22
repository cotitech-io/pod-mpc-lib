// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../IInbox.sol";
import "./PodUser.sol";
import "../mpccodec/MpcAbiCodec.sol";

/**
 * @title PodLibBase
 * @notice Shared POD helpers: codec wiring and default MPC error handler.
 */
abstract contract PodLibBase is PodUser {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    function onDefaultMpcError(bytes32 requestId) external onlyInbox {
        (uint256 code, string memory message) = inbox.getOutboxError(requestId);
        emit ErrorRemoteCall(requestId, code, message);
    }
}
