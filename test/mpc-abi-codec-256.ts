import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import { network } from "hardhat";
import { decodeAbiParameters, encodeAbiParameters, encodeFunctionData, toFunctionSelector } from "viem";
import {
  split256To64Parts,
  combine64PartsTo256,
  split128To64Parts,
  combine64PartsTo128,
  decodeCtUint256FromBytes,
  encodeCtUint256,
  encodeItUint256,
} from "./mpc-codec-helpers.js";

const MPC_PRECOMPILE = "0x0000000000000000000000000000000000000064";

describe("MpcAbiCodec256 - 256-bit type encoding/decoding", async function () {
  describe("Helper functions", function () {
    it("should split 256-bit values correctly", function () {
      // Test with a known value
      const value = (0x1234567890ABCDEFn << 192n) |
                   (0xFEDCBA0987654321n << 128n) |
                   (0x1111222233334444n << 64n) |
                   0x5555666677778888n;
      
      const [highHigh, highLow, lowHigh, lowLow] = split256To64Parts(value);
      
      assert.equal(highHigh, 0x1234567890ABCDEFn);
      assert.equal(highLow, 0xFEDCBA0987654321n);
      assert.equal(lowHigh, 0x1111222233334444n);
      assert.equal(lowLow, 0x5555666677778888n);
    });

    it("should combine 64-bit parts back to 256-bit value", function () {
      const highHigh = 0x1234567890ABCDEFn;
      const highLow = 0xFEDCBA0987654321n;
      const lowHigh = 0x1111222233334444n;
      const lowLow = 0x5555666677778888n;
      
      const combined = combine64PartsTo256(highHigh, highLow, lowHigh, lowLow);
      
      const expected = (highHigh << 192n) | (highLow << 128n) | (lowHigh << 64n) | lowLow;
      assert.equal(combined, expected);
    });

    it("should round-trip 256-bit values through split/combine", function () {
      const testValues = [
        0n,
        1n,
        (1n << 64n) - 1n, // max 64-bit
        (1n << 128n) - 1n, // max 128-bit
        (1n << 192n) - 1n, // max 192-bit
        (1n << 256n) - 1n, // max 256-bit
        0x123456789ABCDEFn, // arbitrary value
        BigInt("0x" + "FF".repeat(32)), // max uint256
      ];

      for (const value of testValues) {
        const parts = split256To64Parts(value);
        const combined = combine64PartsTo256(...parts);
        assert.equal(combined, value, `Round-trip failed for value ${value.toString(16)}`);
      }
    });

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
      const expected = (high << 64n) | low;
      
      assert.equal(combined, expected);
    });
  });

  describe("ABI encoding/decoding", function () {
    it("should encode and decode ctUint256", function () {
      const highHigh = 100n;
      const highLow = 200n;
      const lowHigh = 300n;
      const lowLow = 400n;

      const encoded = encodeCtUint256(highHigh, highLow, lowHigh, lowLow);
      const decoded = decodeCtUint256FromBytes(encoded);

      assert.equal(decoded.highHigh, highHigh);
      assert.equal(decoded.highLow, highLow);
      assert.equal(decoded.lowHigh, lowHigh);
      assert.equal(decoded.lowLow, lowLow);
    });

    it("should encode and decode ctUint256 with large values", function () {
      const highHigh = 0x1234567890ABCDEFn;
      const highLow = 0xFEDCBA0987654321n;
      const lowHigh = 0x1111222233334444n;
      const lowLow = 0x5555666677778888n;

      const encoded = encodeCtUint256(highHigh, highLow, lowHigh, lowLow);
      const decoded = decodeCtUint256FromBytes(encoded);

      assert.equal(decoded.highHigh, highHigh);
      assert.equal(decoded.highLow, highLow);
      assert.equal(decoded.lowHigh, lowHigh);
      assert.equal(decoded.lowLow, lowLow);
    });

    it("should encode itUint256 structure", function () {
      const ciphertextParts: [bigint, bigint, bigint, bigint] = [100n, 200n, 300n, 400n];
      const signatures: [[`0x${string}`, `0x${string}`], [`0x${string}`, `0x${string}`]] = [
        ["0x1234", "0x5678"],
        ["0xabcd", "0xef01"],
      ];

      const encoded = encodeItUint256(ciphertextParts, signatures);
      
      // Verify it's valid ABI-encoded bytes
      assert.ok(encoded.startsWith("0x"));
      assert.ok(encoded.length > 10);
    });

    it("should decode itUint256 structure from encoded bytes", function () {
      const ciphertextParts: [bigint, bigint, bigint, bigint] = [100n, 200n, 300n, 400n];
      const signatures: [[`0x${string}`, `0x${string}`], [`0x${string}`, `0x${string}`]] = [
        ["0x1234", "0x5678"],
        ["0xabcd", "0xef01"],
      ];

      const encoded = encodeItUint256(ciphertextParts, signatures);
      
      // Decode it back
      const [decoded] = decodeAbiParameters(
        [
          {
            type: "tuple",
            components: [
              {
                type: "tuple",
                name: "ciphertext",
                components: [
                  {
                    type: "tuple",
                    name: "high",
                    components: [
                      { type: "uint256", name: "high" },
                      { type: "uint256", name: "low" },
                    ],
                  },
                  {
                    type: "tuple",
                    name: "low",
                    components: [
                      { type: "uint256", name: "high" },
                      { type: "uint256", name: "low" },
                    ],
                  },
                ],
              },
              {
                type: "bytes[2][2]",
                name: "signature",
              },
            ],
          },
        ],
        encoded
      );

      const ct = (decoded as any).ciphertext;
      assert.equal(ct.high.high, 100n);
      assert.equal(ct.high.low, 200n);
      assert.equal(ct.low.high, 300n);
      assert.equal(ct.low.low, 400n);
    });
  });

  describe("Value conversions for encryption", function () {
    it("should correctly prepare 256-bit value for encryption as 4 separate 64-bit values", function () {
      // Simulate encrypting a 256-bit value
      // The value 42 should be stored entirely in the lowLow part
      const value = 42n;
      const [highHigh, highLow, lowHigh, lowLow] = split256To64Parts(value);
      
      assert.equal(highHigh, 0n);
      assert.equal(highLow, 0n);
      assert.equal(lowHigh, 0n);
      assert.equal(lowLow, 42n);
    });

    it("should handle 256-bit addition result correctly", function () {
      // Simulate: a + b where a = 42, b = 100
      // Result should be 142, entirely in lowLow
      const a = 42n;
      const b = 100n;
      const sum = a + b;
      
      const parts = split256To64Parts(sum);
      const reconstructed = combine64PartsTo256(...parts);
      
      assert.equal(reconstructed, sum);
    });

    it("should handle large 256-bit values requiring all 4 parts", function () {
      // Create a value that uses all 4 parts
      const highHigh = 1n;
      const highLow = 2n;
      const lowHigh = 3n;
      const lowLow = 4n;
      
      const fullValue = combine64PartsTo256(highHigh, highLow, lowHigh, lowLow);
      const [h1, h2, l1, l2] = split256To64Parts(fullValue);
      
      assert.equal(h1, highHigh);
      assert.equal(h2, highLow);
      assert.equal(l1, lowHigh);
      assert.equal(l2, lowLow);
    });
  });
});

describe("MpcAbiCodec256 - Contract integration", async function () {
  const { viem } = await network.connect({ network: "hardhat" });
  const publicClient = await viem.getPublicClient();
  const [wallet] = await viem.getWalletClients();

  let harness: any;
  let target: any;

  const buildCall = async (functionName: string, args: any[]) => {
    const data = encodeFunctionData({
      abi: harness.abi,
      functionName,
      args,
    });
    const result = await publicClient.call({ to: harness.address, data });
    const [callData] = decodeAbiParameters(
      [{ type: "bytes" }],
      result.data ?? "0x"
    );
    return callData;
  };

  before(async function () {
    const mock = await viem.deployContract("MockExtendedOperations", []);
    const bytecode = (await publicClient.getCode({
      address: mock.address,
    })) as `0x${string}` | undefined;
    await publicClient.request({
      method: "hardhat_setCode" as any,
      params: [MPC_PRECOMPILE, bytecode ?? "0x"] as any,
    });

    harness = await viem.deployContract("MpcAbiCodecHarness", []);
    target = await viem.deployContract("MpcAbiCodecTests", []);
  });

  it("encodes itUint256 type mapped to gtUint256", async function () {
    // Test encoding of itUint256 with 4 ciphertext values
    // The harness buildAndReencodeItTypes function takes values[7-10] for itUint256
    // values[7] = high.high, values[8] = high.low, values[9] = low.high, values[10] = low.low
    // Note: The mock MPC precompile adds 1 to each value during validation
    
    const expectedData = encodeFunctionData({
      abi: target.abi,
      functionName: "setItTypes",
      args: [
        2n,  // gtBool (1+1)
        3n,  // gtUint8 (2+1)
        4n,  // gtUint16 (3+1)
        5n,  // gtUint32 (4+1)
        6n,  // gtUint64 (5+1)
        { high: 7n, low: 8n }, // gtUint128 (6+1, 7+1)
        { high: { high: 101n, low: 201n }, low: { high: 301n, low: 401n } }, // gtUint256 (each +1)
        { value: [13n, 14n] }, // gtString (12+1, 13+1)
      ],
    });
    const selector = expectedData.slice(0, 10) as `0x${string}`;
    
    // values array: [itBool, itUint8, itUint16, itUint32, itUint64, itUint128.high, itUint128.low, 
    //                itUint256.high.high, itUint256.high.low, itUint256.low.high, itUint256.low.low]
    const callData = await buildCall("buildAndReencodeItTypes", [
      selector,
      [1n, 2n, 3n, 4n, 5n, 6n, 7n, 100n, 200n, 300n, 400n], // 11 values
      [12n, 13n],
      ["0x01", "0x02"],
    ]);
    
    assert.equal(callData, expectedData);

    const txHash = await wallet.sendTransaction({
      to: target.address,
      data: callData,
    });
    await publicClient.waitForTransactionReceipt({ hash: txHash });

    assert.equal(await target.read.lastGtBool(), 2n);
    assert.equal(await target.read.lastGtUint64(), 6n);
  });

  it("verifies gtUint256 structure encoding matches expected ABI format", async function () {
    // Verify the ABI encoding of gtUint256 matches what MpcCore expects
    // gtUint256 = { gtUint128 high, gtUint128 low }
    // gtUint128 = { gtUint64 high, gtUint64 low }
    
    const gtUint256Value = {
      high: { high: 0x1111n, low: 0x2222n },
      low: { high: 0x3333n, low: 0x4444n },
    };

    const encoded = encodeAbiParameters(
      [
        {
          type: "tuple",
          components: [
            {
              type: "tuple",
              name: "high",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
            {
              type: "tuple",
              name: "low",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
          ],
        },
      ],
      [gtUint256Value]
    );

    // Decode and verify
    const [decoded] = decodeAbiParameters(
      [
        {
          type: "tuple",
          components: [
            {
              type: "tuple",
              name: "high",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
            {
              type: "tuple",
              name: "low",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
          ],
        },
      ],
      encoded
    );

    assert.equal((decoded as any).high.high, 0x1111n);
    assert.equal((decoded as any).high.low, 0x2222n);
    assert.equal((decoded as any).low.high, 0x3333n);
    assert.equal((decoded as any).low.low, 0x4444n);
  });
});

describe("MpcAbiCodec256 - Callback decoding", async function () {
  it("should decode ctUint256 from callback bytes", function () {
    // Simulate what the Inbox would receive as callback data
    // The callback data is abi.encode(ctUint256)
    const ctHighHigh = 0x1111111111111111n;
    const ctHighLow = 0x2222222222222222n;
    const ctLowHigh = 0x3333333333333333n;
    const ctLowLow = 0x4444444444444444n;

    const callbackData = encodeAbiParameters(
      [
        {
          type: "tuple",
          components: [
            {
              type: "tuple",
              name: "high",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
            {
              type: "tuple",
              name: "low",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
          ],
        },
      ],
      [
        {
          high: { high: ctHighHigh, low: ctHighLow },
          low: { high: ctLowHigh, low: ctLowLow },
        },
      ]
    );

    const decoded = decodeCtUint256FromBytes(callbackData);

    assert.equal(decoded.highHigh, ctHighHigh);
    assert.equal(decoded.highLow, ctHighLow);
    assert.equal(decoded.lowHigh, ctLowHigh);
    assert.equal(decoded.lowLow, ctLowLow);
  });

  it("should decode ctUint256 from receiveC callback wrapper", function () {
    // Simulate the full receiveC(bytes) callback encoding
    // receiveC receives bytes which contains the encoded ctUint256
    const ctHighHigh = 100n;
    const ctHighLow = 200n;
    const ctLowHigh = 300n;
    const ctLowLow = 400n;

    // First, encode the ctUint256 as bytes (this is what the COTI side sends)
    const ctUint256Encoded = encodeAbiParameters(
      [
        {
          type: "tuple",
          components: [
            {
              type: "tuple",
              name: "high",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
            {
              type: "tuple",
              name: "low",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
          ],
        },
      ],
      [
        {
          high: { high: ctHighHigh, low: ctHighLow },
          low: { high: ctLowHigh, low: ctLowLow },
        },
      ]
    );

    // Then, encode it as the bytes parameter for receiveC
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
      args: [ctUint256Encoded],
    });

    // Now decode the receiveC data to get the bytes argument
    const selector = receiveCData.slice(0, 10);
    const expectedSelector = toFunctionSelector("receiveC(bytes)");
    assert.equal(selector, expectedSelector);

    // Decode the bytes argument
    const argsData = `0x${receiveCData.slice(10)}` as `0x${string}`;
    const [bytesArg] = decodeAbiParameters(
      [{ type: "bytes" }],
      argsData
    );

    // Finally decode the ctUint256 from the bytes
    const decoded = decodeCtUint256FromBytes(bytesArg as `0x${string}`);

    assert.equal(decoded.highHigh, ctHighHigh);
    assert.equal(decoded.highLow, ctHighLow);
    assert.equal(decoded.lowHigh, ctLowHigh);
    assert.equal(decoded.lowLow, ctLowLow);
  });

  it("should round-trip a 256-bit value through encode/decode", function () {
    // Test with a known 256-bit value
    const originalValue = (1n << 200n) + (1n << 150n) + (1n << 100n) + (1n << 50n) + 12345n;
    const [highHigh, highLow, lowHigh, lowLow] = split256To64Parts(originalValue);

    // Encode as ctUint256
    const encoded = encodeCtUint256(highHigh, highLow, lowHigh, lowLow);

    // Decode
    const decoded = decodeCtUint256FromBytes(encoded);

    // Reconstruct
    const reconstructed = combine64PartsTo256(
      decoded.highHigh,
      decoded.highLow,
      decoded.lowHigh,
      decoded.lowLow
    );

    assert.equal(reconstructed, originalValue);
  });

  it("should handle maximum uint256 value", function () {
    const maxUint256 = (1n << 256n) - 1n;
    const [highHigh, highLow, lowHigh, lowLow] = split256To64Parts(maxUint256);

    // Each part should be max uint64
    const maxUint64 = (1n << 64n) - 1n;
    assert.equal(highHigh, maxUint64);
    assert.equal(highLow, maxUint64);
    assert.equal(lowHigh, maxUint64);
    assert.equal(lowLow, maxUint64);

    // Round-trip
    const encoded = encodeCtUint256(highHigh, highLow, lowHigh, lowLow);
    const decoded = decodeCtUint256FromBytes(encoded);
    const reconstructed = combine64PartsTo256(
      decoded.highHigh,
      decoded.highLow,
      decoded.lowHigh,
      decoded.lowLow
    );

    assert.equal(reconstructed, maxUint256);
  });

  it("should decode mixed callback with ctUint256 and other types", function () {
    // Simulate a callback that returns multiple values including ctUint256
    // For example: (address sender, ctUint256 balance, uint64 nonce)
    const sender = "0x1234567890123456789012345678901234567890";
    const ctHighHigh = 11n;
    const ctHighLow = 22n;
    const ctLowHigh = 33n;
    const ctLowLow = 44n;
    const nonce = 99n;

    const mixedCallbackData = encodeAbiParameters(
      [
        { type: "address" },
        {
          type: "tuple",
          components: [
            {
              type: "tuple",
              name: "high",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
            {
              type: "tuple",
              name: "low",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
          ],
        },
        { type: "uint64" },
      ],
      [
        sender as `0x${string}`,
        {
          high: { high: ctHighHigh, low: ctHighLow },
          low: { high: ctLowHigh, low: ctLowLow },
        },
        nonce,
      ]
    );

    // Decode
    const [decodedSender, decodedBalance, decodedNonce] = decodeAbiParameters(
      [
        { type: "address" },
        {
          type: "tuple",
          components: [
            {
              type: "tuple",
              name: "high",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
            {
              type: "tuple",
              name: "low",
              components: [
                { type: "uint256", name: "high" },
                { type: "uint256", name: "low" },
              ],
            },
          ],
        },
        { type: "uint64" },
      ],
      mixedCallbackData
    );

    assert.equal((decodedSender as string).toLowerCase(), sender.toLowerCase());
    assert.equal((decodedBalance as any).high.high, ctHighHigh);
    assert.equal((decodedBalance as any).high.low, ctHighLow);
    assert.equal((decodedBalance as any).low.high, ctLowHigh);
    assert.equal((decodedBalance as any).low.low, ctLowLow);
    assert.equal(decodedNonce, nonce);
  });
});

// Re-export for consumers that imported from this file
export {
  split256To64Parts,
  combine64PartsTo256,
  split128To64Parts,
  combine64PartsTo128,
  decodeCtUint256FromBytes,
  encodeCtUint256,
  encodeItUint256,
} from "./mpc-codec-helpers.js";
