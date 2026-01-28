// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { MpcLib } from "../../mpc/MpcLib.sol";
import "../../mpccodec/MpcAbiCodec.sol";
import "../../IInbox.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

interface IPErc20Coti {
    function transferFrom(address from, address to, gtUint64 amount) external;
}

contract PErc20 is MpcLib {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    /// @notice Create the example privacy ERC20 contract.
    /// @param _inbox The inbox contract address.
    constructor(address _inbox) {
        setInbox(_inbox);
    }

    mapping(bytes32 => ctUint64) public balanceOf;

    function transfer(address to, itUint64 calldata amount) external {
        IInbox.MpcMethodCall memory methodCall =
            MpcAbiCodec.create(IPErc20Coti.transferFrom.selector, 3)
            .addArgument(msg.sender) // For gt data type, we use it equivalent, which is user encrypted
            .addArgument(to)
            .addArgument(amount)
            .build();

        IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            PErc20.updateBalanceCallback.selector,
            MpcLib.onDefaultMpcError.selector
        );
    }

    function updateBalanceCallback(bytes memory data) external onlyInbox {
        (
            bytes32 fromHash,
            ctUint64 fromBalanceResponse,
            bytes32 toHash,
            ctUint64 toBalanceResponse
        ) = abi.decode(data, (bytes32, ctUint64, bytes32, ctUint64));

        balanceOf[fromHash] = fromBalanceResponse;
        balanceOf[toHash] = toBalanceResponse;
    }
}