// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../IInbox.sol";
import "./MpcUser.sol";
import "../mpccodec/MpcAbiCodec.sol";
import "./coti-side/ICommonMpcMethods.sol";

abstract contract MpcLib is MpcUser {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    function add(
        itUint64 calldata a,
        itUint64 calldata b,
        address cOwner,
        bytes4 callbackSelector,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        IInbox.MpcMethodCall memory methodCall =
            MpcAbiCodec.create(ICommonMpcMethods.add.selector, 3)
            .addArgument(a) // For gt data type, we use it equivalent, which is user encrypted
            .addArgument(b)
            .addArgument(cOwner)
            .build();

        return IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            callbackSelector,
            errorSelector
        );
    }

    function onDefaultMpcError(bytes32 requestId) external onlyInbox {
        (uint code, string memory message) = inbox.getOutboxError(requestId);
        emit ErrorRemoteCall(requestId, code, message);
    }
}



