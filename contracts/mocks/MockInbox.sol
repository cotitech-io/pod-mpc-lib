// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

interface IMpcExecutor {
    function add(itUint64 calldata a, itUint64 calldata b, address cOwner) external;
    function simplyValidate(itUint64 calldata value) external returns (ctUint64);
}

contract MockInbox {
    bytes public lastResponse;
    bytes public lastError;
    bool public lastSuccess;

    event ResponseStored(bytes response);
    event ErrorStored(bytes errorData);

    function respond(bytes memory data) external {
        lastResponse = data;
        emit ResponseStored(data);
    }

    function triggerAdd(
        address executor,
        itUint64 calldata a,
        itUint64 calldata b,
        address cOwner
    ) external {
        lastResponse = "";
        lastError = "";
        lastSuccess = false;
        (bool success, bytes memory returnData) = executor.call(
            abi.encodeWithSelector(IMpcExecutor.add.selector, a, b, cOwner)
        );
        if (!success) {
            lastError = returnData;
            emit ErrorStored(returnData);
            return;
        }
        lastSuccess = true;
    }

    function triggerValidate(
        address executor,
        itUint64 calldata value
    ) external {
        lastResponse = "";
        lastError = "";
        lastSuccess = false;
        (bool success, bytes memory returnData) = executor.call(
            abi.encodeWithSelector(IMpcExecutor.simplyValidate.selector, value)
        );
        if (!success) {
            lastError = returnData;
            emit ErrorStored(returnData);
            return;
        }
        lastResponse = returnData;
        lastSuccess = true;
        emit ResponseStored(returnData);
    }
}

