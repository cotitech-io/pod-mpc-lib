// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../IInbox.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

/**
 * @title MpcAbiCodec
 * @notice This contract is used to encode and decode MpcMethodCall structs.
 */
library MpcAbiCodec {
    enum MpcDataType {
        UINT256,
        ADDRESS, // include other system types for coded
        BYTES32,
        STRING,
        BYTES,
        UINT256_ARRAY,
        ADDRESS_ARRAY,
        BYTES32_ARRAY,
        STRING_ARRAY,
        BYTES_ARRAY,
        IT_BOOL,
        IT_UINT8,
        IT_UINT16,
        IT_UINT32,
        IT_UINT64,
        IT_UINT128,
        IT_UINT256,
        IT_STRING
    }

    struct MpcMethodCallContext {
        IInbox.MpcMethodCall methodCall;
        bytes[] data;
        uint dataSize;
        uint argIndex;
    }
    
    function create(bytes4 selector, uint argCount) internal pure returns (MpcMethodCallContext memory) {
        return MpcMethodCallContext({
            methodCall: IInbox.MpcMethodCall({
            selector: selector,
            data: new bytes(0),
            datatypes: new bytes8[](argCount),
            datalens: new bytes32[](argCount)
        }),
        data: new bytes[](argCount),
        dataSize: 0,
        argIndex: 0
        });
    }

    /**
     * @notice Add an argument to the method call context
     * @param methodCall The method call
     * @param arg the argument to add
     * @return The updated method call
     */
    function addArgument(MpcMethodCallContext memory methodCall, uint256 arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.UINT256);
    }

    function addArgument(MpcMethodCallContext memory methodCall, address arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.ADDRESS);
    }

    function addArgument(MpcMethodCallContext memory methodCall, itUint64 memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.IT_UINT64);
    }

    function addArgument(MpcMethodCallContext memory methodCall, itBool memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.IT_BOOL);
    }

    function addArgument(MpcMethodCallContext memory methodCall, itUint8 memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.IT_UINT8);
    }

    function addArgument(MpcMethodCallContext memory methodCall, itUint16 memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.IT_UINT16);
    }

    function addArgument(MpcMethodCallContext memory methodCall, itUint32 memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.IT_UINT32);
    }

    function addArgument(MpcMethodCallContext memory methodCall, itUint128 memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.IT_UINT128);
    }

    function addArgument(MpcMethodCallContext memory methodCall, itUint256 memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.IT_UINT256);
    }

    function addArgument(MpcMethodCallContext memory methodCall, itString memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.IT_STRING);
    }

    function addArgument(MpcMethodCallContext memory methodCall, bytes32 arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.BYTES32);
    }

    function addArgument(MpcMethodCallContext memory methodCall, string memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.STRING);
    }

    function addArgument(MpcMethodCallContext memory methodCall, bytes memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.BYTES);
    }

    function addArgument(MpcMethodCallContext memory methodCall, uint256[] memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.UINT256_ARRAY);
    }

    function addArgument(MpcMethodCallContext memory methodCall, address[] memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.ADDRESS_ARRAY);
    }

    function addArgument(MpcMethodCallContext memory methodCall, bytes32[] memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.BYTES32_ARRAY);
    }

    function addArgument(MpcMethodCallContext memory methodCall, string[] memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.STRING_ARRAY);
    }

    function addArgument(MpcMethodCallContext memory methodCall, bytes[] memory arg)
    internal pure returns (MpcMethodCallContext memory) {
        return _appendArgument(methodCall, abi.encode(arg), MpcDataType.BYTES_ARRAY);
    }

    /**
     * @notice Build the method call from the context by resizing the data
     * @param methodCall The method call context
     * @return The method call
     */
    function build(MpcMethodCallContext memory methodCall) internal pure returns (IInbox.MpcMethodCall memory) {
        bytes memory resized = new bytes(methodCall.dataSize);
        uint cursor = 0;
        for (uint i = 0; i < methodCall.argIndex; i++) {
            bytes memory chunk = methodCall.data[i];
            methodCall.methodCall.datalens[i] = bytes32(chunk.length);
            for (uint j = 0; j < chunk.length; j++) {
                resized[cursor + j] = chunk[j];
            }
            cursor += chunk.length;
        }

        methodCall.methodCall.data = resized;
        return methodCall.methodCall;
    }

    function reEncodeWithGt(IInbox.MpcMethodCall memory data) internal returns (bytes memory) {
        uint argCount = data.datatypes.length;
        require(data.datalens.length == argCount, "MpcAbiCodec: invalid datalens");
        bytes memory encodedArgs = data.data;

        bytes[] memory processed = new bytes[](argCount);
        bool[] memory isDynamic = new bool[](argCount);
        uint[] memory staticWords = new uint[](argCount);
        uint totalTailSize = 0;

        uint cursor = 0;
        for (uint i = 0; i < argCount; i++) {
            uint argLen = uint(uint256(data.datalens[i]));
            require(cursor + argLen <= encodedArgs.length, "MpcAbiCodec: arg out of bounds");

            bytes memory argData = _slice(encodedArgs, cursor, argLen);
            cursor += argLen;

            MpcDataType dataType = _decodeType(data.datatypes[i]);
            (bytes memory encodedArg, bool dynamicType, uint words) = _normalizeArg(argData, dataType);
            processed[i] = encodedArg;
            isDynamic[i] = dynamicType;
            staticWords[i] = words;
            if (dynamicType) {
                require(encodedArg.length >= 32, "MpcAbiCodec: invalid dynamic arg");
                totalTailSize += (encodedArg.length - 32);
            } else {
                require(encodedArg.length == words * 32, "MpcAbiCodec: invalid static arg");
            }
        }
        require(cursor == encodedArgs.length, "MpcAbiCodec: trailing data");

        uint headSize = 0;
        for (uint i = 0; i < argCount; i++) {
            headSize += isDynamic[i] ? 32 : (staticWords[i] * 32);
        }
        bytes memory recoded = new bytes(4 + headSize + totalTailSize);
        bytes4 selector = data.selector;
        assembly {
            mstore(add(recoded, 32), selector)
        }

        uint tailCursor = 0;
        uint headCursor = 0;
        for (uint i = 0; i < argCount; i++) {
            if (isDynamic[i]) {
                uint offset = headSize + tailCursor;
                _writeWord(recoded, 4 + headCursor, offset);
                bytes memory tailData = processed[i];
                uint tailLen = tailData.length - 32;
                _copyBytes(recoded, 4 + headSize + tailCursor, tailData, 32, tailLen);
                tailCursor += tailLen;
                headCursor += 32;
            } else {
                bytes memory staticData = processed[i];
                _copyBytes(recoded, 4 + headCursor, staticData, 0, staticData.length);
                headCursor += staticData.length;
            }
        }

        return recoded;
    }

    function _appendArgument(
        MpcMethodCallContext memory methodCall,
        bytes memory encodedArg,
        MpcDataType dataType
    ) internal pure returns (MpcMethodCallContext memory) {
        require(methodCall.argIndex < methodCall.methodCall.datatypes.length, "MpcAbiCodec: too many args");

        methodCall.methodCall.datatypes[methodCall.argIndex] = bytes8(uint64(uint8(dataType)));
        methodCall.data[methodCall.argIndex] = encodedArg;
        methodCall.dataSize += encodedArg.length;
        methodCall.argIndex += 1;
        return methodCall;
    }

    function _readUint256(bytes memory data, uint offset) internal pure returns (uint256 value) {
        assembly {
            value := mload(add(add(data, 32), offset))
        }
    }

    function _writeWord(bytes memory data, uint offset, uint256 value) internal pure {
        assembly {
            mstore(add(add(data, 32), offset), value)
        }
    }

    function _slice(bytes memory data, uint offset, uint length) internal pure returns (bytes memory result) {
        result = new bytes(length);
        for (uint i = 0; i < length; i++) {
            result[i] = data[offset + i];
        }
    }

    function _decodeType(bytes8 dataType) internal pure returns (MpcDataType) {
        return MpcDataType(uint8(uint64(dataType)));
    }

    function _normalizeArg(bytes memory argData, MpcDataType dataType)
    internal returns (bytes memory encodedArg, bool dynamicType, uint staticWordCount) {
        if (dataType == MpcDataType.UINT256) {
            return (argData, false, 1);
        }

        if (dataType == MpcDataType.ADDRESS) {
            return (argData, false, 1);
        }

        if (dataType == MpcDataType.BYTES32) {
            return (argData, false, 1);
        }

        if (dataType == MpcDataType.IT_UINT64) {
            itUint64 memory itValue = abi.decode(argData, (itUint64));
            gtUint64 gtValue = MpcCore.validateCiphertext(itValue);
            return (abi.encode(gtUint64.unwrap(gtValue)), false, 1);
        }

        if (dataType == MpcDataType.IT_BOOL) {
            itBool memory itValue = abi.decode(argData, (itBool));
            gtBool gtValue = MpcCore.validateCiphertext(itValue);
            return (abi.encode(gtBool.unwrap(gtValue)), false, 1);
        }

        if (dataType == MpcDataType.IT_UINT8) {
            itUint8 memory itValue = abi.decode(argData, (itUint8));
            gtUint8 gtValue = MpcCore.validateCiphertext(itValue);
            return (abi.encode(gtUint8.unwrap(gtValue)), false, 1);
        }

        if (dataType == MpcDataType.IT_UINT16) {
            itUint16 memory itValue = abi.decode(argData, (itUint16));
            gtUint16 gtValue = MpcCore.validateCiphertext(itValue);
            return (abi.encode(gtUint16.unwrap(gtValue)), false, 1);
        }

        if (dataType == MpcDataType.IT_UINT32) {
            itUint32 memory itValue = abi.decode(argData, (itUint32));
            gtUint32 gtValue = MpcCore.validateCiphertext(itValue);
            return (abi.encode(gtUint32.unwrap(gtValue)), false, 1);
        }

        if (dataType == MpcDataType.IT_UINT128) {
            itUint128 memory itValue = abi.decode(argData, (itUint128));
            gtUint128 memory gtValue = MpcCore.validateCiphertext(itValue);
            bytes memory encoded = abi.encode(gtValue);
            return (encoded, false, encoded.length / 32);
        }

        if (dataType == MpcDataType.IT_UINT256) {
            itUint256 memory itValue = abi.decode(argData, (itUint256));
            gtUint256 memory gtValue = MpcCore.validateCiphertext(itValue);
            bytes memory encoded = abi.encode(gtValue);
            return (encoded, false, encoded.length / 32);
        }

        if (dataType == MpcDataType.IT_STRING) {
            itString memory itValue = abi.decode(argData, (itString));
            gtString memory gtValue = MpcCore.validateCiphertext(itValue);
            return (abi.encode(gtValue), true, 0);
        }

        if (
            dataType == MpcDataType.STRING ||
            dataType == MpcDataType.BYTES ||
            dataType == MpcDataType.UINT256_ARRAY ||
            dataType == MpcDataType.ADDRESS_ARRAY ||
            dataType == MpcDataType.BYTES32_ARRAY ||
            dataType == MpcDataType.STRING_ARRAY ||
            dataType == MpcDataType.BYTES_ARRAY
        ) {
            return (argData, true, 0);
        }

        revert("MpcAbiCodec: unknown type");
    }

    function _copyBytes(
        bytes memory dest,
        uint destOffset,
        bytes memory src,
        uint srcOffset,
        uint length
    ) internal pure {
        if (length == 0) {
            return;
        }
        assembly {
            let destPtr := add(add(dest, 32), destOffset)
            let srcPtr := add(add(src, 32), srcOffset)

            let remaining := length
            for { } gt(remaining, 31) { } {
                mstore(destPtr, mload(srcPtr))
                destPtr := add(destPtr, 32)
                srcPtr := add(srcPtr, 32)
                remaining := sub(remaining, 32)
            }

            if gt(remaining, 0) {
                let mask := sub(shl(mul(remaining, 8), 1), 1)
                let srcWord := and(mload(srcPtr), mask)
                let destWord := and(mload(destPtr), not(mask))
                mstore(destPtr, or(destWord, srcWord))
            }
        }
    }
}