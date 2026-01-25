// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "../mpc/MpcLib.sol";

contract MpcAdder is MpcLib {
    event AddRequest(bytes32 requestId);

    ctUint64 private _result;

    constructor(address _inbox) {
        setInbox(_inbox);
    }

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

    function receiveC(bytes memory data) external onlyInbox {
        _result = abi.decode(data, (ctUint64));
    }

    function resultCiphertext() external view returns (ctUint64) {
        return _result;
    }
}



