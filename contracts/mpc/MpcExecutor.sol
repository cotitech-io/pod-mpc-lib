// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IPodMpcLib.sol";
import "../IInbox.sol";
import "../InboxUser.sol";

contract MpcExecutor is IPodMpcLib, InboxUser {

    constructor(address _inbox) {
        setInbox(_inbox);
    }

    /**
     * This function is called remotely, 
     * 
     * @param a Encrypted a
     * @param b Encrypted b
     * @param cOwner The owner of the result
     */
    function add(uint256 a, uint256 b, address cOwner) external onlyInbox {
        // TODO:
        // 1. validate a and b
        // calculate c,
        // encrypt c with address cOwner
        // return c
    }
}