// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../mpc/MpcLib.sol";

contract MpcAdder is MpcLib {
    event AddRequest(bytes32 requestId);

    ctUint64 private _result;

    /// @notice Create an MPC adder bound to an inbox.
    /// @param _inbox The inbox contract address.
    constructor(address _inbox) {
        setInbox(_inbox);
    }

    /// @notice Send an MPC add request using encrypted inputs.
    /// @param a Encrypted input a (itUint64).
    /// @param b Encrypted input b (itUint64).
    function add(itUint64 calldata a, itUint64 calldata b) external {
        bytes32 requestId = MpcLib.add(
            a,
            b,
            msg.sender,
            MpcAdder.receiveC.selector,
            MpcLib.onDefaultMpcError.selector
        );
        emit AddRequest(requestId);
    }

    /// @notice Receive the response and store the ciphertext result.
    /// @param data The response payload containing the ciphertext.
    function receiveC(bytes memory data) external onlyInbox {
        _result = abi.decode(data, (ctUint64));
    }

    /// @notice Return the last received ciphertext result.
    function resultCiphertext() external view returns (ctUint64) {
        return _result;
    }
}



