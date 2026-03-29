// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "./IInbox.sol";

interface IInboxMiner {
    /// @dev Mined payload: `targetFee` / `callerFee` are **gas unit** budgets (same as {IInbox.Request}).
    struct MinedRequest {
        bytes32 requestId;
        address sourceContract;
        address targetContract;
        IInbox.MpcMethodCall methodCall;
        bytes4 callbackSelector;
        bytes4 errorSelector;
        bool isTwoWay;
        bytes32 sourceRequestId;
        uint256 targetFee;
        uint256 callerFee;
    }

    /// @notice Process mined requests and errors for a source chain.
    /// @param sourceChainId The source chain ID that produced the mined data.
    /// @param mined The mined requests to process.
    function batchProcessRequests(
        uint sourceChainId, MinedRequest[] memory mined
    ) external;

    /// @notice Withdraws accumulated native token (message fees) to `msg.sender` ({Ownable} owner).
    function collectFees() external;
}
