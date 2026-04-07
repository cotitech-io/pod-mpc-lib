/**
 * Shared ABI encode/decode and split/combine helpers for 128-bit and 256-bit MPC types.
 * Used by mpc-abi-codec-128.ts, mpc-abi-codec-256.ts, and system test utils.
 */
import { decodeAbiParameters, encodeAbiParameters } from "viem";

// --- 128-bit helpers ---

export function split128To64Parts(value: bigint): [bigint, bigint] {
  const mask64 = (1n << 64n) - 1n;
  const low = value & mask64;
  const high = (value >> 64n) & mask64;
  return [high, low];
}

export function combine64PartsTo128(high: bigint, low: bigint): bigint {
  return (high << 64n) | low;
}

const ctUint128Abi = [
  {
    type: "tuple" as const,
    components: [
      { type: "uint256" as const, name: "high" },
      { type: "uint256" as const, name: "low" },
    ],
  },
];

export function decodeCtUint128FromBytes(data: `0x${string}`): { high: bigint; low: bigint } {
  const [decoded] = decodeAbiParameters(ctUint128Abi, data);
  const d = decoded as { high: bigint; low: bigint };
  return { high: d.high, low: d.low };
}

export function encodeCtUint128(high: bigint, low: bigint): `0x${string}` {
  return encodeAbiParameters(
    [{ type: "tuple", components: [{ type: "uint256", name: "high" }, { type: "uint256", name: "low" }] }],
    [{ high, low }]
  );
}

/** itUint128 = { ctUint128 ciphertext, bytes[2] signature } */
export function encodeItUint128(
  ciphertextParts: [bigint, bigint],
  signatures: [`0x${string}`, `0x${string}`]
): `0x${string}` {
  return encodeAbiParameters(
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
    [{ ciphertext: { high: ciphertextParts[0], low: ciphertextParts[1] }, signature: signatures }]
  );
}

// --- 256-bit helpers ---

export function split256To64Parts(value: bigint): [bigint, bigint, bigint, bigint] {
  const mask64 = (1n << 64n) - 1n;
  const lowLow = value & mask64;
  const lowHigh = (value >> 64n) & mask64;
  const highLow = (value >> 128n) & mask64;
  const highHigh = (value >> 192n) & mask64;
  return [highHigh, highLow, lowHigh, lowLow];
}

export function combine64PartsTo256(
  highHigh: bigint,
  highLow: bigint,
  lowHigh: bigint,
  lowLow: bigint
): bigint {
  return (highHigh << 192n) | (highLow << 128n) | (lowHigh << 64n) | lowLow;
}

const ctUint256Abi = [
  {
    type: "tuple" as const,
    components: [
      {
        type: "tuple" as const,
        name: "high",
        components: [
          { type: "uint256" as const, name: "high" },
          { type: "uint256" as const, name: "low" },
        ],
      },
      {
        type: "tuple" as const,
        name: "low",
        components: [
          { type: "uint256" as const, name: "high" },
          { type: "uint256" as const, name: "low" },
        ],
      },
    ],
  },
];

export function decodeCtUint256FromBytes(data: `0x${string}`): {
  highHigh: bigint;
  highLow: bigint;
  lowHigh: bigint;
  lowLow: bigint;
} {
  const [decoded] = decodeAbiParameters(ctUint256Abi, data);
  const d = decoded as { high: { high: bigint; low: bigint }; low: { high: bigint; low: bigint } };
  return {
    highHigh: d.high.high,
    highLow: d.high.low,
    lowHigh: d.low.high,
    lowLow: d.low.low,
  };
}

export function encodeCtUint256(
  highHigh: bigint,
  highLow: bigint,
  lowHigh: bigint,
  lowLow: bigint
): `0x${string}` {
  return encodeAbiParameters(
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
    [{ high: { high: highHigh, low: highLow }, low: { high: lowHigh, low: lowLow } }]
  );
}

/** itUint256 = { ctUint256 ciphertext, bytes[2][2] signature } */
export function encodeItUint256(
  ciphertextParts: [bigint, bigint, bigint, bigint],
  signatures: [[`0x${string}`, `0x${string}`], [`0x${string}`, `0x${string}`]]
): `0x${string}` {
  return encodeAbiParameters(
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
          { type: "bytes[2][2]", name: "signature" },
        ],
      },
    ],
    [
      {
        ciphertext: {
          high: { high: ciphertextParts[0], low: ciphertextParts[1] },
          low: { high: ciphertextParts[2], low: ciphertextParts[3] },
        },
        signature: signatures,
      },
    ]
  );
}
