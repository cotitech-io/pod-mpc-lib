// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../IInbox.sol";
import "../InboxUser.sol";

/// @title PodUser
/// @notice POD base: COTI chain ID, MPC executor address, and owner-gated {configure}.
abstract contract PodUser is InboxUser, Ownable {
    event ErrorRemoteCall(bytes32 requestId, uint256 code, string message);

    address internal mpcExecutorAddress = 0x0000000000000000000000000000000000000000;
    uint256 internal cotiChainId = 2632500;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @dev Internal COTI routing; use {configure} from outside this contract.
    function configureCoti(address _mpcExecutorAddress, uint256 _cotiChainId) internal virtual {
        mpcExecutorAddress = _mpcExecutorAddress;
        cotiChainId = _cotiChainId;
    }

    /// @notice Owner-only: set inbox when `inbox_ != address(0)`; always updates COTI executor and chain id.
    function configure(address inbox_, address mpcExecutor_, uint256 cotiChainId_) external onlyOwner {
        if (inbox_ != address(0)) {
            setInbox(inbox_);
        }
        configureCoti(mpcExecutor_, cotiChainId_);
    }
}
