// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../IInbox.sol";
import "../InboxUser.sol";

/**
 * @title MpcUser
 * @notice This is the base contract for the MPC user contract. It is used to configure the MPC executor
 *         It is also used to send two-way messages to the MpcExecutor contract on the COTI side.
 */
abstract contract MpcUser is InboxUser {
    event ErrorRemoteCall(bytes32 requestId, uint code, string message);

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