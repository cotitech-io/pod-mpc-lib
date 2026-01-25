// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../mpccodec/MpcAbiCodec.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

contract MpcAbiCodecHarness {
    using MpcAbiCodec for MpcAbiCodec.MpcMethodCallContext;

    function buildAndReencodeStatic(
        bytes4 selector,
        uint256 a,
        address b,
        bytes32 c
    ) external returns (bytes memory) {
        MpcAbiCodec.MpcMethodCallContext memory ctx = MpcAbiCodec.create(selector, 3);
        ctx = ctx.addArgument(a);
        ctx = ctx.addArgument(b);
        ctx = ctx.addArgument(c);
        ctx.methodCall.selector = selector;
        return MpcAbiCodec.reEncodeWithGt(ctx.build());
    }

    function buildAndReencodeDynamic(
        bytes4 selector,
        string calldata s,
        bytes calldata data,
        uint256[] calldata nums,
        address[] calldata addrs,
        bytes32[] calldata b32s
    ) external returns (bytes memory) {
        MpcAbiCodec.MpcMethodCallContext memory ctx = MpcAbiCodec.create(selector, 5);
        ctx = ctx.addArgument(s);
        ctx = ctx.addArgument(data);
        ctx = ctx.addArgument(nums);
        ctx = ctx.addArgument(addrs);
        ctx = ctx.addArgument(b32s);
        ctx.methodCall.selector = selector;
        return MpcAbiCodec.reEncodeWithGt(ctx.build());
    }

    function buildAndReencodeMixed(
        bytes4 selector,
        uint256 a,
        itUint64 calldata b,
        string calldata s,
        bytes32 c,
        bytes calldata data
    ) external returns (bytes memory) {
        MpcAbiCodec.MpcMethodCallContext memory ctx = MpcAbiCodec.create(selector, 5);
        ctx = ctx.addArgument(a);
        ctx = ctx.addArgument(b);
        ctx = ctx.addArgument(s);
        ctx = ctx.addArgument(c);
        ctx = ctx.addArgument(data);
        ctx.methodCall.selector = selector;
        return MpcAbiCodec.reEncodeWithGt(ctx.build());
    }

    function buildAndReencodeItTypes(
        bytes4 selector,
        uint256[] calldata values,
        uint256[] calldata stringCts,
        bytes[] calldata stringSigs
    ) external returns (bytes memory) {
        require(values.length == 11, "MpcAbiCodecHarness: invalid values");

        MpcAbiCodec.MpcMethodCallContext memory ctx = MpcAbiCodec.create(selector, 8);
        {
            itBool memory itB = itBool({ciphertext: ctBool.wrap(values[0]), signature: ""});
            ctx = ctx.addArgument(itB);
        }
        {
            itUint8 memory itU8 = itUint8({ciphertext: ctUint8.wrap(values[1]), signature: ""});
            ctx = ctx.addArgument(itU8);
        }
        {
            itUint16 memory itU16 = itUint16({ciphertext: ctUint16.wrap(values[2]), signature: ""});
            ctx = ctx.addArgument(itU16);
        }
        {
            itUint32 memory itU32 = itUint32({ciphertext: ctUint32.wrap(values[3]), signature: ""});
            ctx = ctx.addArgument(itU32);
        }
        {
            itUint64 memory itU64 = itUint64({ciphertext: ctUint64.wrap(values[4]), signature: ""});
            ctx = ctx.addArgument(itU64);
        }
        {
            itUint128 memory itU128 = itUint128({
                ciphertext: ctUint128({high: ctUint64.wrap(values[5]), low: ctUint64.wrap(values[6])}),
                signature: [bytes(""), bytes("")]
            });
            ctx = ctx.addArgument(itU128);
        }
        {
            itUint256 memory itU256 = itUint256({
                ciphertext: ctUint256({
                    high: ctUint128({high: ctUint64.wrap(values[7]), low: ctUint64.wrap(values[8])}),
                    low: ctUint128({high: ctUint64.wrap(values[9]), low: ctUint64.wrap(values[10])})
                }),
                signature: [[bytes(""), bytes("")], [bytes(""), bytes("")]]
            });
            ctx = ctx.addArgument(itU256);
        }
        {
            itString memory itS = _buildItString(stringCts, stringSigs);
            ctx = ctx.addArgument(itS);
        }
        ctx.methodCall.selector = selector;
        return MpcAbiCodec.reEncodeWithGt(ctx.build());
    }

    function _buildItString(uint256[] calldata stringCts, bytes[] calldata stringSigs)
        internal
        pure
        returns (itString memory)
    {
        require(stringCts.length == stringSigs.length, "MpcAbiCodecHarness: len mismatch");

        ctUint64[] memory values = new ctUint64[](stringCts.length);
        for (uint i = 0; i < stringCts.length; i++) {
            values[i] = ctUint64.wrap(stringCts[i]);
        }

        bytes[] memory sigs = new bytes[](stringSigs.length);
        for (uint i = 0; i < stringSigs.length; i++) {
            sigs[i] = stringSigs[i];
        }

        return itString({ciphertext: ctString({value: values}), signature: sigs});
    }
}

