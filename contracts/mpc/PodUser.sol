// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../IInbox.sol";
import "../InboxUser.sol";

/// @title PodUser
/// @notice POD base: COTI chain ID, MPC executor address, and configuration hook.
abstract contract PodUser is InboxUser {
    event ErrorRemoteCall(bytes32 requestId, uint256 code, string message);

    address internal mpcExecutorAddress = 0x0000000000000000000000000000000000000000;
    uint256 internal cotiChainId = 2632500;

    /// @notice Configure the COTI MPC executor address and chain ID.
    /// @param _mpcExecutorAddress The MPC executor contract address.
    /// @param _cotiChainId The COTI chain ID.
    function configureCoti(address _mpcExecutorAddress, uint256 _cotiChainId) public virtual {
        mpcExecutorAddress = _mpcExecutorAddress;
        cotiChainId = _cotiChainId;
    }
}
