// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./InboxUser.sol";

/// @title InboxUserCotiTestnet
/// @notice Mixin that configures {InboxUser} for COTI testnet inbox address.
abstract contract InboxUserCotiTestnet is InboxUser {
    address internal constant COTI_TESTNET_INBOX = 0x0f9A5cD00450Db1217839C35D23D56F96d6331AE;

    constructor() {
        setInbox(COTI_TESTNET_INBOX);
    }
}
