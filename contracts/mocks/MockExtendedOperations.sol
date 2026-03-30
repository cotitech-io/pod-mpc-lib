// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @title MockExtendedOperations
/// @notice Stand-in for COTI `validateCiphertext` during tests.
contract MockExtendedOperations {
    event ValidateCiphertextCalled(bytes1 metaData, uint256 ciphertext, bytes signature);

    /// @notice Echoes `ciphertext + 1` and emits `ValidateCiphertextCalled`.
    /// @param metaData Opaque metadata.
    /// @param ciphertext Input value.
    /// @param signature Opaque signature bytes.
    /// @return result Mocked output.
    function ValidateCiphertext(bytes1 metaData, uint256 ciphertext, bytes calldata signature)
        external
        returns (uint256 result)
    {
        emit ValidateCiphertextCalled(metaData, ciphertext, signature);
        return ciphertext + 1;
    }
}
