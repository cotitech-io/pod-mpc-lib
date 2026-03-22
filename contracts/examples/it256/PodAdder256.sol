// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
import "../../mpc/PodLib.sol";
import "../../mpc/PodLibBase.sol";


contract PodAdder256 is PodLib {
    event AddRequest(bytes32 requestId);

    ctUint256 private _result;

    /// @notice Create an MPC adder bound to an inbox.
    /// @param _inbox The inbox contract address.
    constructor(address _inbox) {
        setInbox(_inbox);
    }

    /// @notice Send an MPC add request using encrypted inputs.
    /// @param a Encrypted input a (itUint256).
    /// @param b Encrypted input b (itUint256).
    function add(itUint256 calldata a, itUint256 calldata b) external {
        bytes32 requestId = add256(
            a,
            b,
            msg.sender,
            PodAdder256.receiveC.selector,
            PodLibBase.onDefaultMpcError.selector
        );
        emit AddRequest(requestId);
    }

    /// @notice Receive the response and store the ciphertext result.
    /// @param data The response payload containing the ciphertext.
    function receiveC(bytes memory data) external onlyInbox {
        _result = abi.decode(data, (ctUint256));
    }

    /// @notice Return the last received ciphertext result.
    function resultCiphertext() external view returns (ctUint256 memory) {
        return _result;
    }
}