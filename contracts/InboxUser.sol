// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./IInbox.sol";

abstract contract InboxUser {
    IInbox public inbox;

    error OnlyInbox(address invalidCaller);

    /// @dev Restrict calls to the configured inbox.
    modifier onlyInbox() {
        if (msg.sender != address(inbox)) {
            revert OnlyInbox(msg.sender);
        }
        _;
    }

    /// @dev Set the inbox contract address.
    /// @param _inbox The inbox address to use.
    function setInbox(address _inbox) internal {
        inbox = IInbox(_inbox);
    }
}