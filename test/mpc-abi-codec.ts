import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import { network } from "hardhat";
import { decodeAbiParameters, encodeAbiParameters, encodeFunctionData, keccak256 } from "viem";

const MPC_PRECOMPILE = "0x0000000000000000000000000000000000000064";

describe("MpcAbiCodec", async function () {
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

  it("encodes static types", async function () {
    const a = 123n;
    const c = "0x00000000000000000000000000000000000000000000000000000000000000aa";
    const expectedData = encodeFunctionData({
      abi: target.abi,
      functionName: "setStatic",
      args: [a, wallet.account.address, c],
    });
    const selector = expectedData.slice(0, 10) as `0x${string}`;

    const callData = await buildCall("buildAndReencodeStatic", [
      selector,
      a,
      wallet.account.address,
      c,
    ]);
    assert.equal(callData, expectedData);

    const txHash = await wallet.sendTransaction({
      to: target.address,
      data: callData,
    });
    await publicClient.waitForTransactionReceipt({ hash: txHash });

    assert.equal(await target.read.lastUint(), a);
    assert.equal(
      (await target.read.lastAddr()).toLowerCase(),
      wallet.account.address.toLowerCase()
    );
    assert.equal(await target.read.lastBytes32(), c);
  });

  it("encodes dynamic types and arrays", async function () {
    const s = "hello";
    const data = "0x11223344";
    const nums = [1n, 2n, 3n];
    const addrs = [wallet.account.address];
    const b32s = [
      "0x0000000000000000000000000000000000000000000000000000000000000011",
      "0x0000000000000000000000000000000000000000000000000000000000000022",
    ] as const;
    const expectedData = encodeFunctionData({
      abi: target.abi,
      functionName: "setDynamic",
      args: [s, data, nums, addrs, b32s],
    });
    const selector = expectedData.slice(0, 10) as `0x${string}`;

    const callData = await buildCall("buildAndReencodeDynamic", [
      selector,
      s,
      data,
      nums,
      addrs,
      b32s,
    ]);
    assert.equal(callData, expectedData);

    const txHash = await wallet.sendTransaction({
      to: target.address,
      data: callData,
    });
    await publicClient.waitForTransactionReceipt({ hash: txHash });

    const expectedHash = keccak256(
      encodeAbiParameters(
        [
          { type: "string" },
          { type: "bytes" },
          { type: "uint256[]" },
          { type: "address[]" },
          { type: "bytes32[]" },
        ],
        [s, data, nums, addrs, b32s]
      )
    );
    assert.equal(await target.read.lastDynamicHash(), expectedHash);
  });

  it("encodes mixed standard and IT types", async function () {
    const a = 777n;
    const itU64 = { ciphertext: 9n, signature: "0x1234" };
    const s = "mixed";
    const c = "0x00000000000000000000000000000000000000000000000000000000000000ff";
    const data = "0xaabbcc";
    const expectedData = encodeFunctionData({
      abi: target.abi,
      functionName: "setMixed",
      args: [a, 10n, s, c, data],
    });
    const selector = expectedData.slice(0, 10) as `0x${string}`;

    const callData = await buildCall("buildAndReencodeMixed", [
      selector,
      a,
      itU64,
      s,
      c,
      data,
    ]);
    assert.equal(callData, expectedData);

    const txHash = await wallet.sendTransaction({
      to: target.address,
      data: callData,
    });
    await publicClient.waitForTransactionReceipt({ hash: txHash });

    const expectedMixedHash = keccak256(
      encodeAbiParameters([{ type: "string" }, { type: "bytes" }], [s, data])
    );

    assert.equal(await target.read.lastUint(), a);
    assert.equal(await target.read.lastGtUint64(), 10n);
    assert.equal(await target.read.lastBytes32(), c);
    assert.equal(await target.read.lastMixedHash(), expectedMixedHash);
  });

  it("encodes IT types mapped to gt types", async function () {
    const expectedData = encodeFunctionData({
      abi: target.abi,
      functionName: "setItTypes",
      args: [
        2n,
        3n,
        4n,
        5n,
        6n,
        { high: 7n, low: 8n },
        { high: { high: 9n, low: 10n }, low: { high: 11n, low: 12n } },
        { value: [13n, 14n] },
      ],
    });
    const selector = expectedData.slice(0, 10) as `0x${string}`;
    const callData = await buildCall("buildAndReencodeItTypes", [
      selector,
      [1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 9n, 10n, 11n],
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
    const expectedItHash = keccak256(
      encodeAbiParameters(
        [
          { type: "uint256" },
          { type: "uint256" },
          { type: "uint256" },
          {
            type: "tuple",
            components: [
              { type: "uint256", name: "high" },
              { type: "uint256", name: "low" },
            ],
          },
          {
            type: "tuple",
            components: [
              {
                type: "tuple",
                components: [
                  { type: "uint256", name: "high" },
                  { type: "uint256", name: "low" },
                ],
                name: "high",
              },
              {
                type: "tuple",
                components: [
                  { type: "uint256", name: "high" },
                  { type: "uint256", name: "low" },
                ],
                name: "low",
              },
            ],
          },
          {
            type: "tuple",
            components: [{ type: "uint256[]", name: "value" }],
          },
        ],
        [
          3n,
          4n,
          5n,
          { high: 7n, low: 8n },
          { high: { high: 9n, low: 10n }, low: { high: 11n, low: 12n } },
          { value: [13n, 14n] },
        ]
      )
    );

    assert.equal(await target.read.lastItHash(), expectedItHash);
  });
});

