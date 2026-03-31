// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../../IInbox.sol";
import "../../mpc/PodLib.sol";
import "../../mpc/PodLibBase.sol";
import "../../mpccodec/MpcAbiCodec.sol";

/// @dev COTI executor hook; must match deployed `transferFrom` on the COTI example.
interface IPErc20Coti {
    function transferFrom(address from, gtUint256 calldata to, gtUint64 amount) external;
}



/// @title PErc20
/// @notice Minimal PoD example: 64-bit balances keyed by hash; two-way inbox to `IPErc20Coti` on COTI.
/// @dev Sample only: no allowances, weak pending-state story, `ctUint64` balance encoding.
contract PErc20 is PodLib {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    mapping(bytes32 => ctUint64) public balanceOf;

    /// @param _inbox Inbox used for {PodLib.setInbox}.
    constructor(address _inbox) PodLibBase(msg.sender) {
        setInbox(_inbox);
    }

    /**
     * @notice Sends a two-way MPC request to move `amount` from `msg.sender` toward the encrypted recipient descriptor `to`.
     * @dev **Gotcha:** `IPErc20Coti.transferFrom` receives `msg.sender` as `from` on COTI; the PoD `from` identity must match
     *      how COTI hashes participants. **Gotcha:** uses {PodLibBase.onDefaultMpcError} for failures—balances are not rolled back here.
     */
    /// @param callbackFeeLocalWei Caller-estimated wei for the callback leg; total is `msg.value`.
    function transfer(itUint256 calldata to, itUint64 calldata amount, uint256 callbackFeeLocalWei) external payable {
        IInbox.MpcMethodCall memory methodCall = MpcAbiCodec.create(IPErc20Coti.transferFrom.selector, 3)
            .addArgument(msg.sender)
            .addArgument(to)
            .addArgument(amount)
            .build();

        _sendTwoWayWithFee(
            msg.value,
            callbackFeeLocalWei,
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            PErc20.updateBalanceCallback.selector,
            PodLibBase.onDefaultMpcError.selector
        );
    }

    /**
     * @notice Inbox callback: writes new ciphertext balances for `fromHash` and `toHash` returned from COTI.
     * @dev **Gotcha:** must only be callable through the inbox (`onlyInbox` on {PodLib}); trust model is entirely executor + codec correctness.
     */
    function updateBalanceCallback(bytes memory data) external onlyInbox {
        (bytes32 fromHash, ctUint64 fromBalanceResponse, bytes32 toHash, ctUint64 toBalanceResponse) = abi.decode(
            data,
            (bytes32, ctUint64, bytes32, ctUint64)
        );

        balanceOf[fromHash] = fromBalanceResponse;
        balanceOf[toHash] = toBalanceResponse;
    }
}
