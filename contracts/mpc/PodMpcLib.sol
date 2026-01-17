// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IPodMpcLib.sol";
import "../IInbox.sol";
import "./MpcUser.sol";

abstract contract PodMpcLib is MpcUser, IPodMpcLib {
    // TODO: Change this to COTI data types
    function add(uint256 a, uint256 b, address cOwner, bytes4 callbackSelector, bytes4 errorSelector
    ) internal returns (bytes32) {
        bytes memory encodedMessage = abi.encodeWithSelector(
            IPodMpcLib.add.selector, a, b, cOwner);
        return IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            encodedMessage,
            callbackSelector,
            errorSelector);
    }
}