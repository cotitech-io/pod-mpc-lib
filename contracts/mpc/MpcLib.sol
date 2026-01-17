// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IPodMpcLib.sol";
import "../IInbox.sol";

contract MpcLib is MpcUser {
    constructor(address _inbox) {
        setInbox(_inbox);
    }
}