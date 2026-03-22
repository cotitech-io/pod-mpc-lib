// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../IInbox.sol";
import "../InboxUser.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

/// @dev Local mock: add64 / gt64 / add128 / add256 only (not full IPodExecutor* surface).
contract MpcExecutorMock is InboxUser {
    event AddResult(uint c, address cOwner);
    event Add128Result(uint high, uint low, address cOwner);
    event Add256Result(uint highHigh, uint highLow, uint lowHigh, uint lowLow, address cOwner);
    event GtResult(uint result, address cOwner);

    /// @notice Create a mock MPC executor bound to an inbox.
    /// @param _inbox The inbox contract address.
    constructor(address _inbox) {
        setInbox(_inbox);
    }

    /// @notice Mock add implementation invoked remotely by the inbox.
    /// @param a Encrypted input a.
    /// @param b Encrypted input b.
    /// @param cOwner The owner of the result.
    function add64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        uint c = uint256(gtUint64.unwrap(a)) + uint256(gtUint64.unwrap(b));
        bytes memory data = abi.encode(c);
        emit AddResult(c, cOwner);
        inbox.respond(data);
    }

    /// @notice Mock gt implementation invoked remotely by the inbox.
    /// @param a Encrypted input a.
    /// @param b Encrypted input b.
    /// @param cOwner The owner of the result.
    function gt64(gtUint64 a, gtUint64 b, address cOwner) external onlyInbox {
        uint result = uint256(gtUint64.unwrap(a)) > uint256(gtUint64.unwrap(b)) ? 1 : 0;
        bytes memory data = abi.encode(result);
        emit GtResult(result, cOwner);
        inbox.respond(data);
    }

    /// @notice Mock add128 implementation invoked remotely by the inbox.
    /// @param a Encrypted input a (gtUint128).
    /// @param b Encrypted input b (gtUint128).
    /// @param cOwner The owner of the result.
    function add128(gtUint128 memory a, gtUint128 memory b, address cOwner) external onlyInbox {
        ctUint128 memory result = ctUint128({
            high: ctUint64.wrap(gtUint64.unwrap(a.high) + gtUint64.unwrap(b.high)),
            low: ctUint64.wrap(gtUint64.unwrap(a.low) + gtUint64.unwrap(b.low))
        });
        bytes memory data = abi.encode(result);
        emit Add128Result(ctUint64.unwrap(result.high), ctUint64.unwrap(result.low), cOwner);
        inbox.respond(data);
    }

    /// @notice Mock add256 implementation invoked remotely by the inbox.
    /// @param a Encrypted input a (gtUint256).
    /// @param b Encrypted input b (gtUint256).
    /// @param cOwner The owner of the result.
    function add256(gtUint256 memory a, gtUint256 memory b, address cOwner) external onlyInbox {
        ctUint256 memory result = _add256Parts(a, b);
        bytes memory data = abi.encode(result);
        emit Add256Result(
            ctUint64.unwrap(result.high.high),
            ctUint64.unwrap(result.high.low),
            ctUint64.unwrap(result.low.high),
            ctUint64.unwrap(result.low.low),
            cOwner
        );
        inbox.respond(data);
    }

    function _add256Parts(gtUint256 memory a, gtUint256 memory b) internal pure returns (ctUint256 memory) {
        return ctUint256({
            high: ctUint128({
                high: ctUint64.wrap(gtUint64.unwrap(a.high.high) + gtUint64.unwrap(b.high.high)),
                low: ctUint64.wrap(gtUint64.unwrap(a.high.low) + gtUint64.unwrap(b.high.low))
            }),
            low: ctUint128({
                high: ctUint64.wrap(gtUint64.unwrap(a.low.high) + gtUint64.unwrap(b.low.high)),
                low: ctUint64.wrap(gtUint64.unwrap(a.low.low) + gtUint64.unwrap(b.low.low))
            })
        });
    }
}