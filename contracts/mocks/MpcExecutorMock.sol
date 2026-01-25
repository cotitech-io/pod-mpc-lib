// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../IInbox.sol";
import "../InboxUser.sol";
import "../mpc/coti-side/ICommonMpcMethods.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

contract MpcExecutorMock is ICommonMpcMethods, InboxUser {
    event AddResult(uint c, address cOwner);

    constructor(address _inbox) {
        setInbox(_inbox);
    }

    /**
     * This function is called remotely, 
     * @param a Encrypted a
     * @param b Encrypted b
     * @param cOwner The owner of the result
     */
    function add(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        uint c = uint256(gtUint64.unwrap(a)) + uint256(gtUint64.unwrap(b));
        bytes memory data = abi.encode(c);
        emit AddResult(c, cOwner);
        inbox.respond(data);
    }
}