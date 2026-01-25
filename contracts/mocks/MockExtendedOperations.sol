// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract MockExtendedOperations {
    event ValidateCiphertextCalled(bytes1 metaData, uint256 ciphertext, bytes signature);

    function ValidateCiphertext(bytes1 metaData, uint256 ciphertext, bytes calldata signature)
        external
        returns (uint256 result)
    {
        emit ValidateCiphertextCalled(metaData, ciphertext, signature);
        return ciphertext + 1;
    }
}

