import assert from "node:assert/strict";
import { before, describe, it } from "node:test";
import { network } from "hardhat";
import { encodeAbiParameters, keccak256, toFunctionSelector, toHex, zeroHash } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { Wallet, ONBOARD_CONTRACT_ADDRESS, transferNative } from "@coti-io/coti-ethers";
import { JsonRpcProvider } from "ethers";
import {
  getLatestRequest,
  getResponseRequestBySource,
  getTupleField,
  logStep,
  mineRequest,
  onboardUser,
  receiptWaitOptions,
  requireEnv,
  requirePrivateKey,
  setupContext,
  type TestContext,
} from "./mpc-test-utils.js";

const BATCH_PROCESS_SELECTOR = toFunctionSelector(
  "batchProcessRequests(uint256,(bytes32,address,address,(bytes4,bytes,bytes8[],bytes32[]),bytes4,bytes4,bool,bytes32)[])"
);

const normalizePrivateKey = (key: string) => (key.startsWith("0x") ? key : `0x${key}`);

const normalizeCiphertext = (ciphertext: unknown): bigint => {
  if (typeof ciphertext === "bigint") {
    return ciphertext;
  }
  if (ciphertext && typeof ciphertext === "object") {
    const maybeValue = (ciphertext as { value?: bigint[] }).value;
    if (Array.isArray(maybeValue) && maybeValue.length > 0) {
      return BigInt(maybeValue[0]);
    }
  }
  return BigInt(ciphertext as any);
};

const encryptUint64 = async (ctx: TestContext, value: bigint) => {
  const inputText = await ctx.crypto.cotiEncryptWallet.encryptValue(
    value,
    ctx.contracts.inboxCoti.address,
    BATCH_PROCESS_SELECTOR
  );
  return {
    ciphertext: normalizeCiphertext(inputText.ciphertext),
    signature: toHex(inputText.signature as any),
  };
};

const encryptUint128 = async (ctx: TestContext, value: bigint) => {
  const hexString = value.toString(16).padStart(32, "0");
  const high = await encryptUint64(ctx, BigInt(`0x${hexString.slice(0, 16)}`));
  const low = await encryptUint64(ctx, BigInt(`0x${hexString.slice(16, 32)}`));
  return {
    ciphertext: { high: high.ciphertext, low: low.ciphertext },
    signature: [high.signature, low.signature],
  };
};

const buildEncryptedInput64 = async (ctx: TestContext, value: bigint) => {
  return encryptUint64(ctx, value);
};

const buildEncryptedInput256 = async (ctx: TestContext, value: bigint) => {
  const hexString = value.toString(16).padStart(64, "0");
  const high = await encryptUint128(ctx, BigInt(`0x${hexString.slice(0, 32)}`));
  const low = await encryptUint128(ctx, BigInt(`0x${hexString.slice(32, 64)}`));
  return {
    ciphertext: { high: high.ciphertext, low: low.ciphertext },
    signature: [high.signature, low.signature],
  };
};

const decryptCtUint64 = async (ciphertext: any, wallet: Wallet) => {
  const value = getTupleField(ciphertext, "ciphertext", 0) ?? getTupleField(ciphertext, "value", 0) ?? ciphertext;
  return wallet.decryptValue(value as bigint);
};


const deriveSecondaryPrivateKey = (primaryKey: string) => {
  const normalized = normalizePrivateKey(primaryKey).slice(2);
  const bytes = Buffer.from(normalized, "hex");
  bytes[bytes.length - 1] ^= 0x01;
  return `0x${bytes.toString("hex")}`;
};

const setupSecondaryUser = async (primaryPrivateKey: string) => {
  const cotiRpcUrl = requireEnv("COTI_TESTNET_RPC_URL");
  const onboardAddress = process.env.COTI_ONBOARD_CONTRACT_ADDRESS || ONBOARD_CONTRACT_ADDRESS;
  const normalizedKey = deriveSecondaryPrivateKey(primaryPrivateKey);
  const provider = new JsonRpcProvider(cotiRpcUrl) as any;
  const fundingWallet = new Wallet(normalizePrivateKey(primaryPrivateKey), provider);
  const wallet = new Wallet(normalizedKey, provider);

  const balance = await provider.getBalance(wallet.address);
  const minBalance = 300_000_000_000_000_000n; // 0.3 native token
  if (balance < minBalance) {
    logStep("Funding wallet B for onboarding");
    const tx = await transferNative(provider, fundingWallet, wallet.address, 1_000_000_000_000_000_000n, 21_000);
    if (!tx) {
      throw new Error("Failed to fund wallet B for onboarding.");
    }
  }

  const fundedBalance = await provider.getBalance(wallet.address);
  if (fundedBalance < minBalance) {
    throw new Error(`Wallet B balance too low for onboarding: ${fundedBalance.toString()} wei.`);
  }

  const userKey = await onboardUser(normalizedKey, cotiRpcUrl, onboardAddress);
  wallet.setAesKey(userKey);
  return { wallet, address: wallet.address as `0x${string}` };
};

describe("PErc20 (system)", async function () {
  const { viem: sepoliaViem } = await network.connect({ network: "hardhat" });
  const { viem: cotiViem } = await network.connect({ network: "cotiTestnet" });

  let ctx: TestContext;
  let pErc20: any;
  let pErc20AsCoti: any;
  let pErc20Coti: any;
  let ownerAddress: `0x${string}`;
  let secondaryUser: { wallet: Wallet; address: `0x${string}` };

  before(async function () {
    ctx = await setupContext({ sepoliaViem, cotiViem });

    const cotiPrivateKey = normalizePrivateKey(requirePrivateKey("COTI_TESTNET_PRIVATE_KEY"));
    const cotiAccount = privateKeyToAccount(cotiPrivateKey as `0x${string}`);
    ownerAddress = cotiAccount.address;
    const hardhatCotiWallet = await sepoliaViem.getWalletClient(ownerAddress);

    logStep("Deploying PErc20 on Hardhat");
    pErc20 = await sepoliaViem.deployContract("PErc20", [ctx.contracts.inboxSepolia.address]);
    pErc20AsCoti = await sepoliaViem.getContractAt("PErc20", pErc20.address, {
      client: {
        public: ctx.sepolia.publicClient,
        wallet: hardhatCotiWallet,
      },
    });

    logStep("Deploying PErc20Coti on COTI");
    pErc20Coti = await cotiViem.deployContract(
      "PErc20Coti",
      [ctx.contracts.inboxCoti.address],
      {
        client: {
          public: ctx.coti.publicClient,
          wallet: ctx.coti.wallet,
        },
      } as any
    );
    await pErc20.write.configureCoti([pErc20Coti.address, ctx.chainIds.coti]);

    secondaryUser = await setupSecondaryUser(cotiPrivateKey);
  });

  it("Should transfer and decode balances on Sepolia", async function () {
    const amount = 250n;
    const totalSupply = 1_000_000n;

    logStep("Test: encrypt transfer inputs");
    const itTo = await buildEncryptedInput256(ctx, BigInt(secondaryUser.address));
    const itAmount = await buildEncryptedInput64(ctx, amount);

    logStep("Test: sending transfer()");
    const txHash = await pErc20AsCoti.write.transfer([itTo, itAmount]);
    logStep(`Test: waiting for tx ${txHash}`);
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });

    logStep("Test: loading latest request");
    const request = await getLatestRequest(ctx.contracts.inboxSepolia);
    const requestId = request.requestId;

    logStep("Test: mining request on COTI");
    await mineRequest(ctx, "coti", BigInt(ctx.chainIds.sepolia), request, "Test");

    const inboxResponse = await ctx.contracts.inboxCoti.read.inboxResponses([requestId]);
    const responseRequestId = getTupleField(inboxResponse, "responseRequestId", 0) as `0x${string}`;
    if (!responseRequestId || responseRequestId === zeroHash) {
      const inboxError = await ctx.contracts.inboxCoti.read.errors([requestId]);
      const errorCode = getTupleField(inboxError, "errorCode", 1);
      const errorMessage = getTupleField(inboxError, "errorMessage", 2);
      throw new Error(
        `COTI execution failed: errorCode=${errorCode} errorMessage=${errorMessage ?? "unknown"}`
      );
    }

    logStep("Test: mining response on Sepolia");
    const responseRequest = await getResponseRequestBySource(ctx.contracts.inboxCoti, requestId, "Test");
    await mineRequest(ctx, "sepolia", ctx.chainIds.coti, responseRequest, "Test");

    const ownerHash = keccak256(encodeAbiParameters([{ type: "address" }], [ownerAddress]));
    const recipientHash = keccak256(encodeAbiParameters([{ type: "address" }], [secondaryUser.address]));
    const ownerBalance = await pErc20.read.balanceOf([ownerHash]);
    const recipientBalance = await pErc20.read.balanceOf([recipientHash]);

    const ownerDecoded = await decryptCtUint64(ownerBalance, ctx.crypto.cotiEncryptWallet);
    const recipientDecoded = await decryptCtUint64(recipientBalance, secondaryUser.wallet);

    logStep(`Test: new balaces. owner=${ownerDecoded} recipient=${recipientDecoded}`);

    assert.equal(ownerDecoded, totalSupply - amount);
    assert.equal(recipientDecoded, amount);
  });
});

