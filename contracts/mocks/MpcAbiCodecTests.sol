// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

contract MpcAbiCodecTests {
    uint256 public lastUint;
    address public lastAddr;
    bytes32 public lastBytes32;
    uint256 public lastGtUint64;
    uint256 public lastGtBool;
    bytes32 public lastDynamicHash;
    bytes32 public lastMixedHash;
    bytes32 public lastItHash;

    function setStatic(uint256 a, address b, bytes32 c) external {
        lastUint = a;
        lastAddr = b;
        lastBytes32 = c;
    }

    function setDynamic(
        string calldata s,
        bytes calldata data,
        uint256[] calldata nums,
        address[] calldata addrs,
        bytes32[] calldata b32s
    ) external {
        lastDynamicHash = keccak256(abi.encode(s, data, nums, addrs, b32s));
    }

    function setMixed(
        uint256 a,
        gtUint64 b,
        string calldata s,
        bytes32 c,
        bytes calldata data
    ) external {
        lastUint = a;
        lastGtUint64 = gtUint64.unwrap(b);
        lastBytes32 = c;
        lastMixedHash = keccak256(abi.encode(s, data));
    }

    function setItTypes(
        gtBool b,
        gtUint8 u8,
        gtUint16 u16,
        gtUint32 u32,
        gtUint64 u64,
        gtUint128 calldata u128,
        gtUint256 calldata u256,
        gtString calldata gs
    ) external {
        lastGtBool = gtBool.unwrap(b);
        lastGtUint64 = gtUint64.unwrap(u64);
        lastItHash = keccak256(abi.encode(u8, u16, u32, u128, u256, gs));
    }
}

