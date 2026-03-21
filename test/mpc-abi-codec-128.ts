import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import { network } from "hardhat";
import { decodeAbiParameters, encodeAbiParameters, encodeFunctionData, toFunctionSelector } from "viem";
import {
  split128To64Parts,
  combine64PartsTo128,
  decodeCtUint128FromBytes,
  encodeCtUint128,
  encodeItUint128,
} from "./mpc-codec-helpers.js";

const MPC_PRECOMPILE = "0x0000000000000000000000000000000000000064";

describe("MpcAbiCodec128 - 128-bit type encoding/decoding", function () {
  describe("Helper functions", function () {
    it("should split 128-bit values correctly", function () {
      const value = (0x1234567890ABCDEFn << 64n) | 0xFEDCBA0987654321n;
      const [high, low] = split128To64Parts(value);
      assert.equal(high, 0x1234567890ABCDEFn);
      assert.equal(low, 0xFEDCBA0987654321n);
    });

    it("should combine 64-bit parts back to 128-bit value", function () {
      const high = 0x1234567890ABCDEFn;
      const low = 0xFEDCBA0987654321n;
      const combined = combine64PartsTo128(high, low);
      assert.equal(combined, (high << 64n) | low);
    });

    it("should round-trip 128-bit values through split/combine", function () {
      const testValues = [
        0n,
        1n,
        (1n << 64n) - 1n,
        (1n << 128n) - 1n,
        0x123456789ABCDEFn,
      ];
      for (const value of testValues) {
        const [high, low] = split128To64Parts(value);
        const combined = combine64PartsTo128(high, low);
        assert.equal(combined, value, `Round-trip failed for ${value.toString(16)}`);
      }
    });
  });

  describe("ABI encoding/decoding", function () {
    it("should encode and decode ctUint128", function () {
      const high = 100n;
      const low = 200n;
      const encoded = encodeCtUint128(high, low);
      const decoded = decodeCtUint128FromBytes(encoded);
      assert.equal(decoded.high, high);
      assert.equal(decoded.low, low);
    });

    it("should encode and decode ctUint128 with large values", function () {
      const high = 0x1234567890ABCDEFn;
      const low = 0xFEDCBA0987654321n;
      const encoded = encodeCtUint128(high, low);
      const decoded = decodeCtUint128FromBytes(encoded);
      assert.equal(decoded.high, high);
      assert.equal(decoded.low, low);
    });

    it("should encode itUint128 structure", function () {
      const ciphertextParts: [bigint, bigint] = [100n, 200n];
      const signatures: [`0x${string}`, `0x${string}`] = ["0x1234", "0x5678"];
      const encoded = encodeItUint128(ciphertextParts, signatures);
      assert.ok(encoded.startsWith("0x"));
      assert.ok(encoded.length > 10);
    });

    it("should decode itUint128 structure from encoded bytes", function () {
      const ciphertextParts: [bigint, bigint] = [100n, 200n];
      const signatures: [`0x${string}`, `0x${string}`] = ["0x1234", "0x5678"];
      const encoded = encodeItUint128(ciphertextParts, signatures);
      const [decoded] = decodeAbiParameters(
        [
          {
            type: "tuple",
            components: [
              {
                type: "tuple",
                name: "ciphertext",
                components: [
                  { type: "uint256", name: "high" },
                  { type: "uint256", name: "low" },
                ],
              },
              { type: "bytes[2]", name: "signature" },
            ],
          },
        ],
        encoded
      );
      const ct = (decoded as any).ciphertext;
      assert.equal(ct.high, 100n);
      assert.equal(ct.low, 200n);
    });
  });

  describe("Value conversions", function () {
    it("should prepare 128-bit value as 2 x 64-bit parts", function () {
      const value = 42n;
      const [high, low] = split128To64Parts(value);
      assert.equal(high, 0n);
      assert.equal(low, 42n);
    });

    it("should handle 128-bit addition result correctly", function () {
      const a = 42n;
      const b = 100n;
      const sum = a + b;
      const [high, low] = split128To64Parts(sum);
      const reconstructed = combine64PartsTo128(high, low);
      assert.equal(reconstructed, sum);
    });
  });
});

describe("MpcAbiCodec128 - Contract integration", async function () {
  const { viem } = await network.connect({ network: "hardhat" });
  const publicClient = await viem.getPublicClient();

  let harness: any;
  let target: any;

  const buildCall = async (functionName: string, args: any[]) => {
    const data = encodeFunctionData({
      abi: harness.abi,
      functionName,
      args,
    });
    const result = await publicClient.call({ to: harness.address, data });
    const [callData] = decodeAbiParameters([{ type: "bytes" }], result.data ?? "0x");
    return callData;
  };

  before(async function () {
    const mock = await viem.deployContract("MockExtendedOperations", []);
    const bytecode = (await publicClient.getCode({ address: mock.address })) as `0x${string}` | undefined;
    await publicClient.request({
      method: "hardhat_setCode" as any,
      params: [MPC_PRECOMPILE, bytecode ?? "0x"] as any,
    });
    harness = await viem.deployContract("MpcAbiCodecHarness", []);
    target = await viem.deployContract("MpcAbiCodecTests", []);
  });

  it("encodes itUint128 type mapped to gtUint128", async function () {
    // Harness buildAndReencodeItTypes: values[5], values[6] are itUint128 high/low.
    // Mock precompile adds 1 to each value during validation.
    const expectedData = encodeFunctionData({
      abi: target.abi,
      functionName: "setItTypes",
      args: [
        2n,
        3n,
        4n,
        5n,
        6n,
        { high: 7n, low: 8n }, // gtUint128 (6+1, 7+1)
        { high: { high: 101n, low: 201n }, low: { high: 301n, low: 401n } },
        { value: [13n, 14n] },
      ],
    });
    const selector = expectedData.slice(0, 10) as `0x${string}`;
    const callData = await buildCall("buildAndReencodeItTypes", [
      selector,
      [1n, 2n, 3n, 4n, 5n, 6n, 7n, 100n, 200n, 300n, 400n],
      [12n, 13n],
      ["0x01", "0x02"],
    ]);
    assert.equal(callData, expectedData);
  });
});

describe("MpcAbiCodec128 - Callback decoding", function () {
  it("should decode ctUint128 from callback bytes", function () {
    const ctHigh = 0x1111111111111111n;
    const ctLow = 0x2222222222222222n;
    const callbackData = encodeCtUint128(ctHigh, ctLow);
    const decoded = decodeCtUint128FromBytes(callbackData);
    assert.equal(decoded.high, ctHigh);
    assert.equal(decoded.low, ctLow);
  });

  it("should decode ctUint128 from receiveC callback wrapper", function () {
    const ctHigh = 100n;
    const ctLow = 200n;
    const ctUint128Encoded = encodeCtUint128(ctHigh, ctLow);
    const receiveCData = encodeFunctionData({
      abi: [
        {
          type: "function",
          name: "receiveC",
          stateMutability: "nonpayable",
          inputs: [{ name: "data", type: "bytes" }],
          outputs: [],
        },
      ],
      functionName: "receiveC",
      args: [ctUint128Encoded],
    });
    const argsData = `0x${receiveCData.slice(10)}` as `0x${string}`;
    const [bytesArg] = decodeAbiParameters([{ type: "bytes" }], argsData);
    const decoded = decodeCtUint128FromBytes(bytesArg as `0x${string}`);
    assert.equal(decoded.high, ctHigh);
    assert.equal(decoded.low, ctLow);
  });

  it("should round-trip a 128-bit value through encode/decode", function () {
    const originalValue = (1n << 100n) + (1n << 50n) + 12345n;
    const [high, low] = split128To64Parts(originalValue);
    const encoded = encodeCtUint128(high, low);
    const decoded = decodeCtUint128FromBytes(encoded);
    const reconstructed = combine64PartsTo128(decoded.high, decoded.low);
    assert.equal(reconstructed, originalValue);
  });

  it("should handle maximum uint128 value", function () {
    const maxUint128 = (1n << 128n) - 1n;
    const [high, low] = split128To64Parts(maxUint128);
    const maxUint64 = (1n << 64n) - 1n;
    assert.equal(high, maxUint64);
    assert.equal(low, maxUint64);
    const encoded = encodeCtUint128(high, low);
    const decoded = decodeCtUint128FromBytes(encoded);
    const reconstructed = combine64PartsTo128(decoded.high, decoded.low);
    assert.equal(reconstructed, maxUint128);
  });
});
