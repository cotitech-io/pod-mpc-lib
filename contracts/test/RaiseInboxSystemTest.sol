// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "../IInbox.sol";
import "../InboxUser.sol";

/**
 * @title RaiseInboxTestCoti
 * @notice COTI target: inbox delivers `triggerRaise`, contract forwards to {IInbox.raise}.
 */
contract RaiseInboxTestCoti is InboxUser {
    constructor(address inboxAddress) {
        setInbox(inboxAddress);
    }

    function triggerRaise(bytes calldata errorPayload) external onlyInbox {
        inbox.raise(errorPayload);
    }
}

/**
 * @title RaiseInboxTestSepolia
 * @notice Hardhat/Sepolia side: starts a two-way call to {RaiseInboxTestCoti} and records the error callback.
 */
contract RaiseInboxTestSepolia is InboxUser {
    bytes4 private constant TRIGGER_RAISE = bytes4(keccak256("triggerRaise(bytes)"));

    uint256 public immutable cotiChainId;
    address public immutable cotiRaiseContract;

    bool public raiseErrorCalled;
    bytes public lastRaiseErrorPayload;
    /// @notice Value of {IInbox.inboxSourceRequestId} when {onRaiseError} ran (must match COTI incoming id for `raise`).
    bytes32 public lastErrorSourceRequestId;

    error ExpectedRaisePathNotSuccess();

    constructor(address inboxAddress, uint256 cotiChainId_, address cotiRaiseContract_) {
        setInbox(inboxAddress);
        cotiChainId = cotiChainId_;
        cotiRaiseContract = cotiRaiseContract_;
    }

    function onSuccess(bytes calldata) external view onlyInbox {
        revert ExpectedRaisePathNotSuccess();
    }

    function onRaiseError(bytes calldata payload) external onlyInbox {
        raiseErrorCalled = true;
        lastRaiseErrorPayload = payload;
        lastErrorSourceRequestId = inbox.inboxSourceRequestId();
    }

    /// @notice Full calldata for `RaiseInboxTestCoti.triggerRaise(bytes)`.
    function startRaiseRoundTrip(bytes calldata raisePayload) external {
        bytes memory data = abi.encodeWithSelector(TRIGGER_RAISE, raisePayload);
        IInbox.MpcMethodCall memory methodCall = IInbox.MpcMethodCall({
            selector: bytes4(0),
            data: data,
            datatypes: new bytes8[](0),
            datalens: new bytes32[](0)
        });
        IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            cotiRaiseContract,
            methodCall,
            this.onSuccess.selector,
            this.onRaiseError.selector
        );
    }
}
