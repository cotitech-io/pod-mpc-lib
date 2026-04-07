// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./PodUser.sol";

/// @title PodUserSepolia
abstract contract PodUserSepolia is PodUser {

    address constant INBOX_ADDRESS = 0xFa158f9e49C8bb77f971c3630EbCD23a8a88D14E;
    uint256 constant COTI_CHAIN_ID = 2632500;
    address constant MPC_EXECUTOR_ADDRESS = 0xC76aaE4F3810fBBd5d96b92DEFeBE0034405Ad9c;

    constructor() {
        setInbox(INBOX_ADDRESS);
        configureCoti(MPC_EXECUTOR_ADDRESS, COTI_CHAIN_ID);
    }
}
