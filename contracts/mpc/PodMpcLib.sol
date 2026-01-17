// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IPodMpcLib.sol";
import "../IInbox.sol";

library PodMpcLib {
    // TODO: Set this after deployment
    address internal constant MPC_EXECUTOR_ADDRESS_COTI_TESTNET = 0x0000000000000000000000000000000000000000;
    address internal constant MPC_EXECUTOR_ADDRESS_COTI_MAINNET = 0x0000000000000000000000000000000000000000;
    bool internal constant isTESTNET = true; // Set to false for mainnet
    uint256 internal constant COTI_TESTNET_CHAIN_ID = 31337;
    uint256 internal constant COTI_MAINNET_CHAIN_ID = 1;

    // TODO: Change this to COTI data types
    function add(IInbox inbox, uint256 a, uint256 b, address cOwner, bytes4 callbackSelector, bytes4 errorSelector
    ) internal returns (bytes32) {
        bytes memory encodedMessage = abi.encodeWithSelector(
            IPodMpcLib.add.selector, a, b, cOwner);
        return inbox.sendTwoWayMessage(
            isTESTNET ? COTI_TESTNET_CHAIN_ID : COTI_MAINNET_CHAIN_ID,
            isTESTNET ? MPC_EXECUTOR_ADDRESS_COTI_TESTNET : MPC_EXECUTOR_ADDRESS_COTI_MAINNET,
            encodedMessage,
            callbackSelector,
            errorSelector);
    }
}