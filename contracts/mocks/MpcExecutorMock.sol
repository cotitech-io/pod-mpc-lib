// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../IInbox.sol";
import "../InboxUser.sol";
import "../mpc/coti-side/ICommonMpcMethods.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

contract MpcExecutorMock is ICommonMpcMethods, InboxUser {
    event AddResult(uint c, address cOwner);

    /// @notice Create a mock MPC executor bound to an inbox.
    /// @param _inbox The inbox contract address.
    constructor(address _inbox) {
        setInbox(_inbox);
    }

    /// @notice Mock add implementation invoked remotely by the inbox.
    /// @param a Encrypted input a.
    /// @param b Encrypted input b.
    /// @param cOwner The owner of the result.
    function add(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        uint c = uint256(gtUint64.unwrap(a)) + uint256(gtUint64.unwrap(b));
        bytes memory data = abi.encode(c);
        emit AddResult(c, cOwner);
        inbox.respond(data);
    }
}