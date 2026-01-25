// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../InboxUser.sol";
import "./ICommonMpcMethods.sol";

contract MpcExecutor is ICommonMpcMethods, InboxUser {
    event AddResult(ctUint64 result, address cOwner);
    event ValidateResult(ctUint64 result, address cOwner);

    constructor(address _inbox) {
        setInbox(_inbox);
    }

    /**
     * This function is called remotely by the Inbox.
     *
     * @param gtA Encrypted a (gtUint64)
     * @param gtB Encrypted b (gtUint64)
     * @param cOwner The owner of the result ciphertext
     */
    function add(gtUint64 gtA, gtUint64 gtB, address cOwner) external onlyInbox {
        gtUint64 gtC = MpcCore.add(gtA, gtB);
        utUint64 memory combined = MpcCore.offBoardCombined(gtC, cOwner);

        emit AddResult(combined.userCiphertext, cOwner);

        bytes memory data = abi.encode(combined.userCiphertext);
        inbox.respond(data);
    }
}



