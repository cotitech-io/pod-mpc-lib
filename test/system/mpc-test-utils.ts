import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { decodeAbiParameters, defineChain, toFunctionSelector, toHex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ONBOARD_CONTRACT_ADDRESS, Wallet as CotiWallet } from "@coti-io/coti-ethers";
import { JsonRpcProvider } from "ethers";

export type TestContext = {
  sepolia: {
    publicClient: any;
    wallet: any;
  };
  coti: {
    publicClient: any;
    wallet: any;
  };
  contracts: {
    inboxSepolia: any;
    inboxCoti: any;
    mpcAdder: any;
    mpcAdderAsCoti: any;
    mpcExecutor: any;
  };
  crypto: {
    userKey: string;
    cotiEncryptWallet: CotiWallet;
  };
  chainIds: {
    sepolia: number;
    coti: bigint;
  };
};

/** Minimum context for `encryptValue` against the COTI inbox (shared by TestContext and PodTestContext). */
export type MpcEncryptContext = {
  crypto: TestContext["crypto"];
  contracts: { inboxCoti: { address: `0x${string}` } };
};

export type RequestMethodCall = {
  selector: `0x${string}`;
  data: `0x${string}`;
  datatypes: `0x${string}`[];
  datalens: `0x${string}`[];
};

export type Request = {
  requestId: `0x${string}`;
  targetChainId: bigint;
  targetContract: `0x${string}`;
  methodCall: RequestMethodCall;
  callerContract: `0x${string}`;
  originalSender: `0x${string}`;
  timestamp: bigint;
  callbackSelector: `0x${string}`;
  errorSelector: `0x${string}`;
  isTwoWay: boolean;
  executed: boolean;
  sourceRequestId: `0x${string}`;
};

// Reads a tuple field by name or index.
export const getTupleField = (value: any, key: string, index: number) => value?.[key] ?? value?.[index];

// Reads a required environment variable.
export const requireEnv = (key: string) => {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing ${key} environment variable`);
  }
  return value;
};

// Reads a required private key (specific key or fallback).
export const requirePrivateKey = (key: string) => {
  const value = process.env[key] ?? process.env.PRIVATE_KEY;
  if (!value) {
    throw new Error(`Missing ${key} or PRIVATE_KEY environment variable`);
  }
  return value;
};

// Normalizes a private key to 0x-prefixed hex.
export const normalizePrivateKey = (key: string) => (key.startsWith("0x") ? key : `0x${key}`);

// Returns a trimmed environment variable or empty string.
export const envOrEmpty = (key: string) => process.env[key]?.trim() ?? "";

// Writes step logs with a common prefix.
export const logStep = (message: string) => {
  console.log(`[mpc-test] ${message}`);
};

// Returns a receipt wait config with consistent polling.
export const receiptWaitOptions = { timeout: 300_000, pollingInterval: 2_000 };

// Onboards a user on COTI and returns the AES key.
const aesKeyCache = new Map<string, string>();
const aesKeyPromiseCache = new Map<string, Promise<string>>();

const normalizePrivateKeyId = (value: string) => value.replace(/^0x/, "").toLowerCase();

export const onboardUser = async (privateKey: string, rpcUrl: string, onboardAddress: string, keyEnv: string = 'COTI_AES_KEY') => {
  const privateKeyId = normalizePrivateKeyId(privateKey);
  const cacheId = `${privateKeyId}:${onboardAddress.toLowerCase()}:${rpcUrl}`;

  const cached = aesKeyCache.get(cacheId);
  if (cached) {
    return cached;
  }

  const envKey = process.env[keyEnv];
  if (envKey) {
    const normalizedEnvKey = envKey.replace(/^0x/, "");
    aesKeyCache.set(cacheId, normalizedEnvKey);
    return normalizedEnvKey;
  }

  const inflight = aesKeyPromiseCache.get(cacheId);
  if (inflight) {
    return inflight;
  }

  const promise = (async () => {
    logStep("Onboarding user via coti-ethers");
    const provider = new JsonRpcProvider(rpcUrl) as any;
    const wallet = new CotiWallet(privateKey, provider);
    await wallet.generateOrRecoverAes(onboardAddress);
    let key = wallet.getUserOnboardInfo()?.aesKey;
    if (!key) {
      throw new Error("Failed to onboard user: missing AES key");
    }
    if (key.startsWith("0x")) {
      key = key.slice(2);
    }
    if (key.length > 32) {
      logStep(`Onboarded AES key length ${key.length}, trimming to 32 hex chars`);
      key = key.slice(0, 32);
    }
    logStep("Onboarding complete");
    aesKeyCache.set(cacheId, key);
    process.env.COTI_AES_KEY = key;
    process.env.COTI_AES_KEY_FOR_PRIVATE_KEY = privateKeyId;
    aesKeyPromiseCache.delete(cacheId);
    return key;
  })();

  aesKeyPromiseCache.set(cacheId, promise);
  return promise;
};

// Parses a raw request tuple into a typed request object.
export const parseRequest = (raw: any): Request => {
  const methodCall = getTupleField(raw, "methodCall", 3);
  const parsedMethodCall: RequestMethodCall = {
    selector: getTupleField(methodCall, "selector", 0),
    data: getTupleField(methodCall, "data", 1),
    datatypes: getTupleField(methodCall, "datatypes", 2) ?? [],
    datalens: getTupleField(methodCall, "datalens", 3) ?? [],
  };

  return {
    requestId: getTupleField(raw, "requestId", 0),
    targetChainId: getTupleField(raw, "targetChainId", 1),
    targetContract: getTupleField(raw, "targetContract", 2),
    methodCall: parsedMethodCall,
    callerContract: getTupleField(raw, "callerContract", 4),
    originalSender: getTupleField(raw, "originalSender", 5),
    timestamp: getTupleField(raw, "timestamp", 6),
    callbackSelector: getTupleField(raw, "callbackSelector", 7),
    errorSelector: getTupleField(raw, "errorSelector", 8),
    isTwoWay: getTupleField(raw, "isTwoWay", 9),
    executed: getTupleField(raw, "executed", 10),
    sourceRequestId: getTupleField(raw, "sourceRequestId", 11),
  };
};

// Loads the latest request from the inbox using getRequests.
export const getLatestRequest = async (inbox: any): Promise<Request> => {
  const requestCount = await inbox.read.getRequestsLen();
  console.log("number of requests in source", requestCount);
  assert.ok(Number(requestCount) > 0);
  const fromIndex = Number(requestCount) - 1;
  const requests = await getRequests(inbox, fromIndex, 1);
  assert.ok(requests.length > 0);
  return requests[0];
};

// Loads a single request from the inbox mapping.
export const getRequest = async (inbox: any, requestId: `0x${string}`): Promise<Request> => {
  const raw = await inbox.read.requests([requestId]);
  return parseRequest(raw);
};

// Loads a range of requests and parses them.
export const getRequests = async (inbox: any, from: number, len: number): Promise<Request[]> => {
  const raw = await inbox.read.getRequests([from, len]);
  return (raw as any[]).map(parseRequest);
};

/** Result of mineRequest; use requestIdUsed for getResponseRequestBySource / getInboxResponse. */
export type MineRequestResult = {
  txHash: `0x${string}`;
  requestIdUsed: `0x${string}`;
};

/** Context shape required by mineRequest (64-bit, wide MPC, etc.). */
export type MineRequestContext = {
  contracts: { inboxCoti: any; inboxSepolia: any };
  coti: { wallet: any; publicClient: any };
  sepolia: { wallet: any; publicClient: any };
};

/** Options for mineRequest / {@link runPodRoundTrip}. */
export type MineRequestOptions = {
  /** Force a specific nonce instead of computing next from lastIncomingRequestId. */
  nonceOverride?: number;
  /** Gas limit for the batchProcessRequests tx (e.g. for 256-bit MPC on COTI testnet). */
  gas?: bigint;
  /**
   * Gas limit for the Hardhat `PodTest*.exec*` tx (outbound POD leg). Large `itUint256` payloads and
   * `sendTwoWayMessage` can require far more than default `eth_estimateGas`; some nodes error with
   * `gas required exceeds allowance (264187)` when the implicit cap is too low.
   */
  hardhatGas?: bigint;
};

// Mines a source request on the target inbox and waits for confirmation.
// Computes next expected requestId so mined nonces stay contiguous; pass nonceOverride to force a nonce.
export const mineRequest = async (
  ctx: MineRequestContext,
  chain: "coti" | "sepolia",
  sourceChainId: bigint,
  request: Request,
  label: string,
  options?: MineRequestOptions
): Promise<MineRequestResult> => {
  console.log("mineRequest", chain, sourceChainId, request, label);
  const inbox = chain === "coti" ? ctx.contracts.inboxCoti : ctx.contracts.inboxSepolia;
  const walletClient = chain === "coti" ? ctx.coti.wallet : ctx.sepolia.wallet;
  const chainLabel = chain.toUpperCase();
  logStep(`${label}: using ${chainLabel} inbox ${inbox.address}`);
  logStep(`${label}: ${chainLabel} inbox wallet ${walletClient?.account?.address ?? "unknown"}`);
  const publicClient = chain === "coti" ? ctx.coti.publicClient : ctx.sepolia.publicClient;
  console.log("reading last incoming request id", sourceChainId);
  const latestMinedRequestId = await inbox.read.lastIncomingRequestId([sourceChainId]);
  logStep(`${label}: latest mined request on ${chainLabel} is ${latestMinedRequestId.toString()}`);

  // Compute next expected requestId so mined nonces stay contiguous (or use override).
  let nextNonce: number;
  const zeroHash =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
  if (options?.nonceOverride !== undefined) {
    nextNonce = options.nonceOverride;
    logStep(`${label}: using nonce override ${nextNonce}`);
  } else {
    const lastId =
      typeof latestMinedRequestId === "string"
        ? latestMinedRequestId
        : String(latestMinedRequestId);
    if (!lastId || lastId === zeroHash) {
      nextNonce = 1;
    } else {
      const unpacked = await inbox.read.unpackRequestId([latestMinedRequestId]);
      const lastNonce = Number(getTupleField(unpacked, "nonce", 1));
      nextNonce = lastNonce + 1;
    }
  }
  const nextRequestId = (await inbox.read.getRequestId([
    sourceChainId,
    nextNonce,
  ])) as `0x${string}`;
  logStep(`${label}: using requestId ${nextRequestId} (nonce ${nextNonce}) for batchProcessRequests`);

  logStep(`${label}: calling batchProcessRequests on ${chainLabel}`);
  const writeOptions: { account: any; gas?: bigint } = {
    account: walletClient?.account,
  };
  if (options?.gas !== undefined) {
    writeOptions.gas = options.gas;
  }
  const txHash = (await inbox.write.batchProcessRequests(
    [
      sourceChainId,
      [
        {
          requestId: nextRequestId,
          sourceContract: request.originalSender,
          targetContract: request.targetContract,
          methodCall: request.methodCall,
          callbackSelector: request.callbackSelector ?? "0x00000000",
          errorSelector: request.errorSelector ?? "0x00000000",
          isTwoWay: request.isTwoWay,
          sourceRequestId: request.sourceRequestId,
        },
      ],
    ],
    writeOptions
  )) as `0x${string}`;
  logStep(`${label}: waiting for ${chainLabel} tx ${txHash}`);
  await publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
  return { txHash, requestIdUsed: nextRequestId };
};

/** Default gas for mining 128-bit MPC requests on COTI testnet (batchProcessRequests). */
export const DEFAULT_COTI_MINE_GAS_MPC_128 = 8_000_000n;

const envBigIntOr = (key: string, fallback: bigint): bigint => {
  const raw = process.env[key]?.trim();
  if (!raw) return fallback;
  try {
    return BigInt(raw);
  } catch {
    return fallback;
  }
};

/**
 * Default gas for mining 256-bit MPC on COTI (`batchProcessRequests` → `MpcExecutor.mul256` etc.).
 * Secret `MpcCore.mul(gtUint256)` is very heavy; 12M often yields inbox errorCode=1 / empty errorMessage (OOG).
 * Override: `COTI_MINE_GAS_MPC_256=60000000`.
 */
export const DEFAULT_COTI_MINE_GAS_MPC_256 = envBigIntOr("COTI_MINE_GAS_MPC_256", 50_000_000n);

/**
 * Returns a mineRequest wrapper that applies a default gas limit when mining on COTI
 * (callers can still override via options.gas).
 */
export function createMineRequestWithDefaultCotiGas(defaultGas: bigint) {
  return async (
    ctx: MineRequestContext,
    chain: "coti" | "sepolia",
    sourceChainId: bigint,
    request: Request,
    label: string,
    options?: MineRequestOptions
  ): Promise<MineRequestResult> => {
    const merged: MineRequestOptions =
      chain === "coti" ? { ...options, gas: options?.gas ?? defaultGas } : options ?? {};
    return mineRequest(ctx, chain, sourceChainId, request, label, merged);
  };
}

// Loads the response request linked to a source request id.
export const getResponseRequestBySource = async (
  inboxCoti: any,
  sourceRequestId: `0x${string}`,
  label: string
): Promise<Request> => {
  const rawResponse = await inboxCoti.read.inboxResponses([sourceRequestId]);
  const responseRequestId = getTupleField(rawResponse, "responseRequestId", 0) as `0x${string}`;
  const hasResponse =
    responseRequestId &&
    responseRequestId !== "0x0000000000000000000000000000000000000000000000000000000000000000";
  if (!hasResponse) {
    const err = await inboxCoti.read.errors([sourceRequestId]);
    const errId = getTupleField(err, "requestId", 0);
    if (errId && errId !== "0x0000000000000000000000000000000000000000000000000000000000000000") {
      const errorCode = getTupleField(err, "errorCode", 1);
      const errorMessage = getTupleField(err, "errorMessage", 2);
      throw new Error(
        `COTI execution failed for ${label}: errorCode=${errorCode} errorMessage=${errorMessage ?? "unknown"}`
      );
    }
    throw new Error(`Missing COTI response for ${label}: responseRequestId not set`);
  }
  logStep(`${label}: responseRequestId=${responseRequestId}`);

  const rawRequest = await inboxCoti.read.requests([responseRequestId]);
  const responseRequest = parseRequest(rawRequest);
  assert.ok(responseRequest);
  return responseRequest;
};

// Encrypts an input value using the COTI wallet.
export const buildEncryptedInput = async (
  ctx: MpcEncryptContext,
  value: bigint
): Promise<{ ciphertext: bigint; signature: `0x${string}` }> => {
  const functionSelector = toFunctionSelector(
      "batchProcessRequests(uint256,(bytes32,address,address,(bytes4,bytes,bytes8[],bytes32[]),bytes4,bytes4,bool,bytes32)[])"
  );
  const inputText = await ctx.crypto.cotiEncryptWallet.encryptValue(
    value,
    ctx.contracts.inboxCoti.address,
    functionSelector
  );
  const signature =
    typeof inputText.signature === "string"
      ? (inputText.signature as `0x${string}`)
      : toHex(inputText.signature as any);
  const ciphertext = normalizeCiphertextInternal(inputText.ciphertext);
  return {
    ciphertext,
    signature,
  };
};

// Decodes a ctUint64-like value into a bigint ciphertext.
export const decodeCtUint64 = (encryptedResult: unknown): bigint => {
  return (
    getTupleField(encryptedResult, "ciphertext", 0) ??
    getTupleField(encryptedResult, "value", 0) ??
    (encryptedResult as bigint)
  );
};

/**
 * Split a 128-bit value into two 64-bit parts (high, low).
 */
export const split128To64Parts = (value: bigint): [bigint, bigint] => {
  const mask64 = (1n << 64n) - 1n;
  const low = value & mask64;
  const high = (value >> 64n) & mask64;
  return [high, low];
};

/**
 * Combine two 64-bit parts into a 128-bit value.
 */
export const combine64PartsTo128 = (high: bigint, low: bigint): bigint => {
  return (high << 64n) | low;
};

/**
 * Split a 256-bit value into four 64-bit parts (high.high, high.low, low.high, low.low).
 */
export const split256To64Parts = (value: bigint): [bigint, bigint, bigint, bigint] => {
  const mask64 = (1n << 64n) - 1n;
  const lowLow = value & mask64;
  const lowHigh = (value >> 64n) & mask64;
  const highLow = (value >> 128n) & mask64;
  const highHigh = (value >> 192n) & mask64;
  return [highHigh, highLow, lowHigh, lowLow];
};

/**
 * Combine four 64-bit parts into a 256-bit value.
 */
export const combine64PartsTo256 = (
  highHigh: bigint,
  highLow: bigint,
  lowHigh: bigint,
  lowLow: bigint
): bigint => {
  return (highHigh << 192n) | (highLow << 128n) | (lowHigh << 64n) | lowLow;
};

// Encrypt a 128-bit value as an itUint128 structure (2 x 64-bit parts, bytes[2] signature).
export const buildEncryptedInput128 = async (
  ctx: MpcEncryptContext,
  value: bigint
): Promise<{
  ciphertext: { high: bigint; low: bigint };
  signature: [`0x${string}`, `0x${string}`];
}> => {
  const functionSelector = toFunctionSelector(
    "batchProcessRequests(uint256,(bytes32,address,address,(bytes4,bytes,bytes8[],bytes32[]),bytes4,bytes4,bool,bytes32)[])"
  );

  const [high, low] = split128To64Parts(value);

  const encryptPart = async (part: bigint) => {
    const inputText = await ctx.crypto.cotiEncryptWallet.encryptValue(
      part,
      ctx.contracts.inboxCoti.address,
      functionSelector
    );
    const signature =
      typeof inputText.signature === "string"
        ? (inputText.signature as `0x${string}`)
        : toHex(inputText.signature as any);
    const ciphertext = normalizeCiphertextInternal(inputText.ciphertext);
    return { ciphertext, signature };
  };

  const encHigh = await encryptPart(high);
  const encLow = await encryptPart(low);

  return {
    ciphertext: { high: encHigh.ciphertext, low: encLow.ciphertext },
    signature: [encHigh.signature, encLow.signature],
  };
};

// Decode a ctUint128 structure into its 2 component ciphertext values.
export const decodeCtUint128 = (
  encryptedResult: unknown
): { high: bigint; low: bigint } => {
  const high = getTupleField(encryptedResult, "high", 0);
  const low = getTupleField(encryptedResult, "low", 1);
  return { high: BigInt(high ?? 0), low: BigInt(low ?? 0) };
};

// Decrypt a ctUint128 result into a 128-bit value.
export const decryptUint128 = (
  encryptedResult: unknown,
  userKey: string,
  decryptFn: (ct: bigint, key: string) => bigint
): bigint => {
  const { high, low } = decodeCtUint128(encryptedResult);
  const decHigh = decryptFn(high, userKey);
  const decLow = decryptFn(low, userKey);
  return combine64PartsTo128(decHigh, decLow);
};

// Encrypt a 256-bit value as an itUint256 structure.
// This encrypts 4 separate 64-bit values and returns the structured type.
export const buildEncryptedInput256 = async (
  ctx: MpcEncryptContext,
  value: bigint
): Promise<{
  ciphertext: {
    high: { high: bigint; low: bigint };
    low: { high: bigint; low: bigint };
  };
  signature: [[`0x${string}`, `0x${string}`], [`0x${string}`, `0x${string}`]];
}> => {
  const functionSelector = toFunctionSelector(
    "batchProcessRequests(uint256,(bytes32,address,address,(bytes4,bytes,bytes8[],bytes32[]),bytes4,bytes4,bool,bytes32)[])"
  );

  // Split the 256-bit value into 4 x 64-bit parts
  const [highHigh, highLow, lowHigh, lowLow] = split256To64Parts(value);

  // Encrypt each 64-bit part
  const encryptPart = async (part: bigint) => {
    const inputText = await ctx.crypto.cotiEncryptWallet.encryptValue(
      part,
      ctx.contracts.inboxCoti.address,
      functionSelector
    );
    const signature =
      typeof inputText.signature === "string"
        ? (inputText.signature as `0x${string}`)
        : toHex(inputText.signature as any);
    const ciphertext = normalizeCiphertextInternal(inputText.ciphertext);
    return { ciphertext, signature };
  };

  const encHighHigh = await encryptPart(highHigh);
  const encHighLow = await encryptPart(highLow);
  const encLowHigh = await encryptPart(lowHigh);
  const encLowLow = await encryptPart(lowLow);

  return {
    ciphertext: {
      high: { high: encHighHigh.ciphertext, low: encHighLow.ciphertext },
      low: { high: encLowHigh.ciphertext, low: encLowLow.ciphertext },
    },
    signature: [
      [encHighHigh.signature, encHighLow.signature],
      [encLowHigh.signature, encLowLow.signature],
    ],
  };
};

// Decode a ctUint256 structure into its 4 component ciphertext values.
export const decodeCtUint256 = (
  encryptedResult: unknown
): { highHigh: bigint; highLow: bigint; lowHigh: bigint; lowLow: bigint } => {
  const high = getTupleField(encryptedResult, "high", 0);
  const low = getTupleField(encryptedResult, "low", 1);

  const highHigh = getTupleField(high, "high", 0);
  const highLow = getTupleField(high, "low", 1);
  const lowHigh = getTupleField(low, "high", 0);
  const lowLow = getTupleField(low, "low", 1);

  return { highHigh, highLow, lowHigh, lowLow };
};

// Decrypt a ctUint256 result into a 256-bit value.
export const decryptUint256 = (
  encryptedResult: unknown,
  userKey: string,
  decryptFn: (ct: bigint, key: string) => bigint
): bigint => {
  const { highHigh, highLow, lowHigh, lowLow } = decodeCtUint256(encryptedResult);

  const decHighHigh = decryptFn(highHigh, userKey);
  const decHighLow = decryptFn(highLow, userKey);
  const decLowHigh = decryptFn(lowHigh, userKey);
  const decLowLow = decryptFn(lowLow, userKey);

  return combine64PartsTo256(decHighHigh, decHighLow, decLowHigh, decLowLow);
};

// Normalizes ciphertext into a bigint.
const normalizeCiphertextInternal = (ciphertext: unknown): bigint => {
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

// Builds the shared MPC test context with deployments and wallets.
export const setupContext = async (params: {
  sepoliaViem: any;
  cotiViem: any;
}): Promise<TestContext> => {
  requireEnv("COTI_TESTNET_RPC_URL");
  requirePrivateKey("COTI_TESTNET_PRIVATE_KEY");

  const sepoliaChainId = parseInt(process.env.HARDHAT_CHAIN_ID || "31337");
  const cotiChainId = BigInt(parseInt(process.env.COTI_TESTNET_CHAIN_ID || "7082400"));
  const cotiDeploymentsPath =
    process.env.COTI_DEPLOYMENTS_PATH || path.resolve(process.cwd(), "deployments", "coti-testnet.json");

  logStep("Preparing chain clients");
  const cotiChain = defineChain({
    id: Number(cotiChainId),
    name: "COTI Testnet",
    nativeCurrency: { name: "COTI", symbol: "COTI", decimals: 18 },
    rpcUrls: {
      default: { http: [requireEnv("COTI_TESTNET_RPC_URL")] },
    },
  });

  const sepoliaPublicClient = await params.sepoliaViem.getPublicClient();
  const cotiPublicClient = await params.cotiViem.getPublicClient({ chain: cotiChain });
  const [sepoliaWallet] = await params.sepoliaViem.getWalletClients();
  const cotiPrivateKeyMain = normalizePrivateKey(requirePrivateKey("COTI_TESTNET_PRIVATE_KEY"));
  const cotiAccount = privateKeyToAccount(cotiPrivateKeyMain as `0x${string}`);
  const hardhatCotiWallet = await params.sepoliaViem.getWalletClient(cotiAccount.address);
  const cotiWallet = await params.cotiViem.getWalletClient(cotiAccount.address, { chain: cotiChain });

  const inboxSepoliaAddress = envOrEmpty("HARDHAT_INBOX_ADDRESS") || envOrEmpty("SEPOLIA_INBOX_ADDRESS");
  const mpcAdderAddress =
    envOrEmpty("HARDHAT_MPC_ADDER_ADDRESS") || envOrEmpty("SEPOLIA_MPC_ADDER_ADDRESS");

  // Cache the COTI deployments to save gas between multiple tests.
  const cachedCoti = await readCotiDeployments(cotiDeploymentsPath);
  const inboxCotiAddress = envOrEmpty("COTI_INBOX_ADDRESS") || cachedCoti.inbox || "";
  const mpcExecutorAddress =
    envOrEmpty("COTI_MPC_EXECUTOR_ADDRESS") || cachedCoti.mpcExecutor || "";

  const reuseSepolia = inboxSepoliaAddress && mpcAdderAddress;
  const reuseCoti =
    envOrEmpty("COTI_REUSE_CONTRACTS").toLowerCase() === "true" &&
    inboxCotiAddress &&
    mpcExecutorAddress;

  let inboxSepolia: any;
  let mpcAdder: any;
  if (reuseSepolia) {
    logStep(`Reusing Hardhat contracts: Inbox=${inboxSepoliaAddress} MpcAdder=${mpcAdderAddress}`);
    inboxSepolia = await params.sepoliaViem.getContractAt("Inbox", inboxSepoliaAddress as `0x${string}`);
    mpcAdder = await params.sepoliaViem.getContractAt("MpcAdder", mpcAdderAddress as `0x${string}`);
  } else {
    logStep("Deploying Hardhat Inbox + MpcAdder");
    inboxSepolia = await params.sepoliaViem.deployContract("Inbox", [BigInt(sepoliaChainId)]);
    mpcAdder = await params.sepoliaViem.deployContract("MpcAdder", [inboxSepolia.address]);
  }

  const mpcAdderAsCoti = await params.sepoliaViem.getContractAt("MpcAdder", mpcAdder.address, {
    client: {
      public: sepoliaPublicClient,
      wallet: hardhatCotiWallet,
    },
  });

  let inboxCoti: any;
  let mpcExecutor: any;
  if (reuseCoti) {
    logStep(`Reusing COTI contracts: Inbox=${inboxCotiAddress} MpcExecutor=${mpcExecutorAddress}`);
    inboxCoti = await params.cotiViem.getContractAt("Inbox", inboxCotiAddress as `0x${string}`, {
      client: { public: cotiPublicClient, wallet: cotiWallet },
    });
    mpcExecutor = await params.cotiViem.getContractAt(
      "MpcExecutor",
      mpcExecutorAddress as `0x${string}`,
      {
        client: { public: cotiPublicClient, wallet: cotiWallet },
      }
    );
  } else {
    logStep("Deploying COTI Inbox + MpcExecutor");
    inboxCoti = await params.cotiViem.deployContract(
      "Inbox",
      [cotiChainId],
      {
        client: {
          public: cotiPublicClient,
          wallet: cotiWallet,
        },
      } as any
    );
    mpcExecutor = await params.cotiViem.deployContract(
      "MpcExecutor",
      [inboxCoti.address],
      {
        client: {
          public: cotiPublicClient,
          wallet: cotiWallet,
        },
      } as any
    );
    await writeCotiDeployments(cotiDeploymentsPath, {
      inbox: inboxCoti.address,
      mpcExecutor: mpcExecutor.address,
    });
    logStep(`Saved COTI deployments to ${cotiDeploymentsPath}`);
  }
  logStep(`COTI inbox address in use: ${inboxCoti.address}`);

  if (!reuseSepolia || !reuseCoti) {
    logStep("Configuring COTI executor + miner");
    await mpcAdder.write.configureCoti([mpcExecutor.address, cotiChainId]);
    const cotiOwner = await inboxCoti.read.owner();
    logStep(`COTI inbox owner ${cotiOwner}`);
    const alreadyMiner = await inboxCoti.read.isMiner([cotiWallet.account.address]);
    if (!alreadyMiner) {
      logStep(`Adding COTI miner ${cotiWallet.account.address}`);
      const addMinerTx = await inboxCoti.write.addMiner([cotiWallet.account.address], {
        account: cotiWallet.account,
      });
      await cotiPublicClient.waitForTransactionReceipt({ hash: addMinerTx, ...receiptWaitOptions });
      const confirmedMiner = await inboxCoti.read.isMiner([cotiWallet.account.address]);
      logStep(`COTI miner confirmed=${confirmedMiner}`);
    } else {
      logStep("COTI miner already configured");
    }
  } else {
    logStep("Skipping configureCoti/addMiner (reused contracts)");
  }

  const sepoliaMiner = sepoliaWallet.account.address;
  const sepoliaAlreadyMiner = await inboxSepolia.read.isMiner([sepoliaMiner]);
  if (!sepoliaAlreadyMiner) {
    logStep(`Adding Sepolia miner ${sepoliaMiner}`);
    await inboxSepolia.write.addMiner([sepoliaMiner]);
  } else {
    logStep("Sepolia miner already configured");
  }

  const cotiRpcUrl = requireEnv("COTI_TESTNET_RPC_URL");
  const cotiProvider = new JsonRpcProvider(cotiRpcUrl) as any;
  const cotiPrivateKey = requirePrivateKey("COTI_TESTNET_PRIVATE_KEY");
  const onboardAddress = process.env.COTI_ONBOARD_CONTRACT_ADDRESS || ONBOARD_CONTRACT_ADDRESS;
  const userKey = await onboardUser(cotiPrivateKey, cotiRpcUrl, onboardAddress);
  const cotiEncryptWallet = new CotiWallet(cotiPrivateKey, cotiProvider as any);
  cotiEncryptWallet.setAesKey(userKey);

  logStep("Setup complete");

  return {
    sepolia: { publicClient: sepoliaPublicClient, wallet: sepoliaWallet },
    coti: { publicClient: cotiPublicClient, wallet: cotiWallet },
    contracts: { inboxSepolia, inboxCoti, mpcAdder, mpcAdderAsCoti, mpcExecutor },
    crypto: { userKey, cotiEncryptWallet },
    chainIds: { sepolia: sepoliaChainId, coti: cotiChainId },
  };
};

/** Context for PodAdder128 / PodAdder256 system tests (same shape as TestContext, different adder contract). */
export type TestContextWideMpc = {
  sepolia: TestContext["sepolia"];
  coti: TestContext["coti"];
  contracts: Omit<TestContext["contracts"], "mpcAdder" | "mpcAdderAsCoti"> & {
    mpcAdder: any;
    mpcAdderAsCoti: any;
  };
  crypto: TestContext["crypto"];
  chainIds: TestContext["chainIds"];
};

/** Configuration for {@link setupContextWideMpc} (128 vs 256 adder + deployments file + env keys). */
export type MpcWideSetupConfig = {
  podAdderContractName: "PodAdder128" | "PodAdder256";
  cotiDeploymentsFile: string;
  envHardhatMpcAdder: string;
  envSepoliaMpcAdder: string;
};

/**
 * Deploy/reuse Inbox + PodAdder128 or PodAdder256 on Hardhat and Inbox + MpcExecutor on COTI.
 * Same flow as {@link setupContext} but parameterized for wide MPC adder contracts.
 */
export const setupContextWideMpc = async (
  params: { sepoliaViem: any; cotiViem: any },
  config: MpcWideSetupConfig
): Promise<TestContextWideMpc> => {
  requireEnv("COTI_TESTNET_RPC_URL");
  requirePrivateKey("COTI_TESTNET_PRIVATE_KEY");

  const sepoliaChainId = parseInt(process.env.HARDHAT_CHAIN_ID || "31337");
  const cotiChainId = BigInt(parseInt(process.env.COTI_TESTNET_CHAIN_ID || "7082400"));
  const cotiDeploymentsPath =
    process.env.COTI_DEPLOYMENTS_PATH ||
    path.resolve(process.cwd(), "deployments", config.cotiDeploymentsFile);

  logStep("Preparing chain clients");
  const cotiChain = defineChain({
    id: Number(cotiChainId),
    name: "COTI Testnet",
    nativeCurrency: { name: "COTI", symbol: "COTI", decimals: 18 },
    rpcUrls: {
      default: { http: [requireEnv("COTI_TESTNET_RPC_URL")] },
    },
  });

  const sepoliaPublicClient = await params.sepoliaViem.getPublicClient();
  const cotiPublicClient = await params.cotiViem.getPublicClient({ chain: cotiChain });
  const [sepoliaWallet] = await params.sepoliaViem.getWalletClients();
  const cotiPrivateKeyMain = normalizePrivateKey(requirePrivateKey("COTI_TESTNET_PRIVATE_KEY"));
  const cotiAccount = privateKeyToAccount(cotiPrivateKeyMain as `0x${string}`);
  const hardhatCotiWallet = await params.sepoliaViem.getWalletClient(cotiAccount.address);
  const cotiWallet = await params.cotiViem.getWalletClient(cotiAccount.address, { chain: cotiChain });

  const inboxSepoliaAddress =
    envOrEmpty("HARDHAT_INBOX_ADDRESS") || envOrEmpty("SEPOLIA_INBOX_ADDRESS");
  const mpcAdderAddress =
    envOrEmpty(config.envHardhatMpcAdder) || envOrEmpty(config.envSepoliaMpcAdder);

  const cachedCoti = await readCotiDeployments(cotiDeploymentsPath);
  const inboxCotiAddress = envOrEmpty("COTI_INBOX_ADDRESS") || cachedCoti.inbox || "";
  const mpcExecutorAddress =
    envOrEmpty("COTI_MPC_EXECUTOR_ADDRESS") || cachedCoti.mpcExecutor || "";

  const reuseSepolia = !!(inboxSepoliaAddress && mpcAdderAddress);
  const reuseCoti =
    envOrEmpty("COTI_REUSE_CONTRACTS").toLowerCase() === "true" &&
    !!inboxCotiAddress &&
    !!mpcExecutorAddress;

  let inboxSepolia: any;
  let mpcAdder: any;
  if (reuseSepolia) {
    logStep(
      `Reusing Hardhat contracts: Inbox=${inboxSepoliaAddress} ${config.podAdderContractName}=${mpcAdderAddress}`
    );
    inboxSepolia = await params.sepoliaViem.getContractAt("Inbox", inboxSepoliaAddress as `0x${string}`);
    mpcAdder = await params.sepoliaViem.getContractAt(
      config.podAdderContractName,
      mpcAdderAddress as `0x${string}`
    );
  } else {
    logStep(`Deploying Hardhat Inbox + ${config.podAdderContractName}`);
    inboxSepolia = await params.sepoliaViem.deployContract("Inbox", [BigInt(sepoliaChainId)]);
    mpcAdder = await params.sepoliaViem.deployContract(config.podAdderContractName, [
      inboxSepolia.address,
    ]);
  }

  const mpcAdderAsCoti = await params.sepoliaViem.getContractAt(
    config.podAdderContractName,
    mpcAdder.address,
    {
      client: {
        public: sepoliaPublicClient,
        wallet: hardhatCotiWallet,
      },
    }
  );

  let inboxCoti: any;
  let mpcExecutor: any;
  if (reuseCoti) {
    logStep(`Reusing COTI contracts: Inbox=${inboxCotiAddress} MpcExecutor=${mpcExecutorAddress}`);
    inboxCoti = await params.cotiViem.getContractAt("Inbox", inboxCotiAddress as `0x${string}`, {
      client: { public: cotiPublicClient, wallet: cotiWallet },
    });
    mpcExecutor = await params.cotiViem.getContractAt(
      "MpcExecutor",
      mpcExecutorAddress as `0x${string}`,
      {
        client: { public: cotiPublicClient, wallet: cotiWallet },
      }
    );
  } else {
    logStep("Deploying COTI Inbox + MpcExecutor");
    inboxCoti = await params.cotiViem.deployContract(
      "Inbox",
      [cotiChainId],
      {
        client: {
          public: cotiPublicClient,
          wallet: cotiWallet,
        },
      } as any
    );
    mpcExecutor = await params.cotiViem.deployContract(
      "MpcExecutor",
      [inboxCoti.address],
      {
        client: {
          public: cotiPublicClient,
          wallet: cotiWallet,
        },
      } as any
    );
    await writeCotiDeployments(cotiDeploymentsPath, {
      inbox: inboxCoti.address,
      mpcExecutor: mpcExecutor.address,
    });
    logStep(`Saved COTI deployments to ${cotiDeploymentsPath}`);
  }
  logStep(`COTI inbox address in use: ${inboxCoti.address}`);

  if (!reuseSepolia || !reuseCoti) {
    logStep("Configuring COTI executor + miner");
    await mpcAdder.write.configureCoti([mpcExecutor.address, cotiChainId]);
    const cotiOwner = await inboxCoti.read.owner();
    logStep(`COTI inbox owner ${cotiOwner}`);
    const alreadyMiner = await inboxCoti.read.isMiner([cotiWallet.account.address]);
    if (!alreadyMiner) {
      logStep(`Adding COTI miner ${cotiWallet.account.address}`);
      const addMinerTx = await inboxCoti.write.addMiner([cotiWallet.account.address], {
        account: cotiWallet.account,
      });
      await cotiPublicClient.waitForTransactionReceipt({ hash: addMinerTx, ...receiptWaitOptions });
      const confirmedMiner = await inboxCoti.read.isMiner([cotiWallet.account.address]);
      logStep(`COTI miner confirmed=${confirmedMiner}`);
    } else {
      logStep("COTI miner already configured");
    }
  } else {
    logStep("Skipping configureCoti/addMiner (reused contracts)");
  }

  const sepoliaMiner = sepoliaWallet.account.address;
  const sepoliaAlreadyMiner = await inboxSepolia.read.isMiner([sepoliaMiner]);
  if (!sepoliaAlreadyMiner) {
    logStep(`Adding Sepolia miner ${sepoliaMiner}`);
    await inboxSepolia.write.addMiner([sepoliaMiner]);
  } else {
    logStep("Sepolia miner already configured");
  }

  const cotiRpcUrl = requireEnv("COTI_TESTNET_RPC_URL");
  const cotiProvider = new JsonRpcProvider(cotiRpcUrl) as any;
  const cotiPrivateKey = requirePrivateKey("COTI_TESTNET_PRIVATE_KEY");
  const onboardAddress = process.env.COTI_ONBOARD_CONTRACT_ADDRESS || ONBOARD_CONTRACT_ADDRESS;
  const userKey = await onboardUser(cotiPrivateKey, cotiRpcUrl, onboardAddress);
  const cotiEncryptWallet = new CotiWallet(cotiPrivateKey, cotiProvider as any);
  cotiEncryptWallet.setAesKey(userKey);

  logStep("Setup complete");

  return {
    sepolia: { publicClient: sepoliaPublicClient, wallet: sepoliaWallet },
    coti: { publicClient: cotiPublicClient, wallet: cotiWallet },
    contracts: {
      inboxSepolia,
      inboxCoti,
      mpcAdder,
      mpcAdderAsCoti,
      mpcExecutor,
    },
    crypto: { userKey, cotiEncryptWallet },
    chainIds: { sepolia: sepoliaChainId, coti: cotiChainId },
  };
};

export async function getCotiCrypto(privateKey: string, rpcUrl: string, keyEnv: string) {
  const cotiProvider = new JsonRpcProvider(rpcUrl) as any;
  const normalizedKey = normalizePrivateKey(privateKey);
  const cotiEncryptWallet = new CotiWallet(normalizedKey, cotiProvider as any);
  const onboardAddress = process.env.COTI_ONBOARD_CONTRACT_ADDRESS || ONBOARD_CONTRACT_ADDRESS;
  const userKey = await onboardUser(normalizedKey, rpcUrl, onboardAddress, keyEnv);
  cotiEncryptWallet.setAesKey(userKey);
  return { cotiEncryptWallet, userKey };
}

// Reads cached COTI deployments from disk.
const readCotiDeployments = async (deploymentsPath: string) => {
  try {
    const raw = await fs.readFile(deploymentsPath, "utf8");
    return JSON.parse(raw) as { inbox?: string; mpcExecutor?: string };
  } catch {
    return {};
  }
};

// Writes cached COTI deployments to disk.
const writeCotiDeployments = async (
  deploymentsPath: string,
  payload: { inbox: string; mpcExecutor: string }
) => {
  await fs.mkdir(path.dirname(deploymentsPath), { recursive: true });
  const data = {
    ...payload,
    updatedAt: new Date().toISOString(),
  };
  await fs.writeFile(deploymentsPath, JSON.stringify(data, null, 2));
};

// ---------------------------------------------------------------------------
// Pod harness (PodTest64 / PodTest128 / PodTest256)
// ---------------------------------------------------------------------------

export type PodTestContractName = "PodTest64" | "PodTest128" | "PodTest256";

const podTestEnvKeys = (name: PodTestContractName) => {
  switch (name) {
    case "PodTest64":
      return { hh: "HARDHAT_POD_TEST64_ADDRESS", sep: "SEPOLIA_POD_TEST64_ADDRESS" };
    case "PodTest128":
      return { hh: "HARDHAT_POD_TEST128_ADDRESS", sep: "SEPOLIA_POD_TEST128_ADDRESS" };
    case "PodTest256":
      return { hh: "HARDHAT_POD_TEST256_ADDRESS", sep: "SEPOLIA_POD_TEST256_ADDRESS" };
  }
};

export type PodTestContext = {
  sepolia: TestContext["sepolia"];
  coti: TestContext["coti"];
  contracts: {
    inboxSepolia: any;
    inboxCoti: any;
    mpcExecutor: any;
    podTest: any;
    podTestAsCoti: any;
  };
  crypto: TestContext["crypto"];
  chainIds: TestContext["chainIds"];
  podContractName: PodTestContractName;
};

/**
 * Like {@link setupContext} but deploys PodTest64/128/256 on Hardhat.
 * Reuses the same COTI inbox + MpcExecutor cache as other MPC tests.
 * After upgrading executor ops, pass `forceRedeployCotiExecutor: true`, set `COTI_REUSE_CONTRACTS=false`,
 * or delete `deployments/coti-testnet.json` so COTI picks up a matching `MpcExecutor`.
 */
export const setupPodTestContext = async (params: {
  sepoliaViem: any;
  cotiViem: any;
  podContractName: PodTestContractName;
  /** When true with `COTI_REUSE_CONTRACTS=true`, redeploy only `MpcExecutor` and keep the cached inbox. */
  forceRedeployCotiExecutor?: boolean;
}): Promise<PodTestContext> => {
  requireEnv("COTI_TESTNET_RPC_URL");
  requirePrivateKey("COTI_TESTNET_PRIVATE_KEY");

  const { hh, sep } = podTestEnvKeys(params.podContractName);
  const sepoliaChainId = parseInt(process.env.HARDHAT_CHAIN_ID || "31337");
  const cotiChainId = BigInt(parseInt(process.env.COTI_TESTNET_CHAIN_ID || "7082400"));
  const cotiDeploymentsPath =
    process.env.COTI_DEPLOYMENTS_PATH || path.resolve(process.cwd(), "deployments", "coti-testnet.json");

  logStep("Preparing chain clients (pod test harness)");
  const cotiChain = defineChain({
    id: Number(cotiChainId),
    name: "COTI Testnet",
    nativeCurrency: { name: "COTI", symbol: "COTI", decimals: 18 },
    rpcUrls: {
      default: { http: [requireEnv("COTI_TESTNET_RPC_URL")] },
    },
  });

  const sepoliaPublicClient = await params.sepoliaViem.getPublicClient();
  const cotiPublicClient = await params.cotiViem.getPublicClient({ chain: cotiChain });
  const [sepoliaWallet] = await params.sepoliaViem.getWalletClients();
  const cotiPrivateKeyMain = normalizePrivateKey(requirePrivateKey("COTI_TESTNET_PRIVATE_KEY"));
  const cotiAccount = privateKeyToAccount(cotiPrivateKeyMain as `0x${string}`);
  const hardhatCotiWallet = await params.sepoliaViem.getWalletClient(cotiAccount.address);
  const cotiWallet = await params.cotiViem.getWalletClient(cotiAccount.address, { chain: cotiChain });

  const inboxSepoliaAddress = envOrEmpty("HARDHAT_INBOX_ADDRESS") || envOrEmpty("SEPOLIA_INBOX_ADDRESS");
  const podAddress = envOrEmpty(hh) || envOrEmpty(sep);

  const cachedCoti = await readCotiDeployments(cotiDeploymentsPath);
  const inboxCotiAddress = envOrEmpty("COTI_INBOX_ADDRESS") || cachedCoti.inbox || "";
  const mpcExecutorAddress =
    envOrEmpty("COTI_MPC_EXECUTOR_ADDRESS") || cachedCoti.mpcExecutor || "";

  const reuseSepolia = !!(inboxSepoliaAddress && podAddress);
  const envReuseCoti = envOrEmpty("COTI_REUSE_CONTRACTS").toLowerCase() === "true";
  const cotiHasCache = !!inboxCotiAddress && !!mpcExecutorAddress;
  const forceRedeployCotiExecutor = params.forceRedeployCotiExecutor === true;
  const reuseCotiFull = envReuseCoti && cotiHasCache && !forceRedeployCotiExecutor;

  let inboxSepolia: any;
  let podTest: any;
  if (reuseSepolia) {
    logStep(`Reusing Hardhat: Inbox=${inboxSepoliaAddress} ${params.podContractName}=${podAddress}`);
    inboxSepolia = await params.sepoliaViem.getContractAt("Inbox", inboxSepoliaAddress as `0x${string}`);
    podTest = await params.sepoliaViem.getContractAt(
      params.podContractName,
      podAddress as `0x${string}`
    );
  } else {
    logStep(`Deploying Hardhat Inbox + ${params.podContractName}`);
    inboxSepolia = await params.sepoliaViem.deployContract("Inbox", [BigInt(sepoliaChainId)]);
    podTest = await params.sepoliaViem.deployContract(params.podContractName, [inboxSepolia.address]);
  }

  const podTestAsCoti = await params.sepoliaViem.getContractAt(params.podContractName, podTest.address, {
    client: {
      public: sepoliaPublicClient,
      wallet: hardhatCotiWallet,
    },
  });

  let inboxCoti: any;
  let mpcExecutor: any;
  if (reuseCotiFull) {
    logStep(`Reusing COTI contracts: Inbox=${inboxCotiAddress} MpcExecutor=${mpcExecutorAddress}`);
    inboxCoti = await params.cotiViem.getContractAt("Inbox", inboxCotiAddress as `0x${string}`, {
      client: { public: cotiPublicClient, wallet: cotiWallet },
    });
    mpcExecutor = await params.cotiViem.getContractAt(
      "MpcExecutor",
      mpcExecutorAddress as `0x${string}`,
      {
        client: { public: cotiPublicClient, wallet: cotiWallet },
      }
    );
  } else if (envReuseCoti && forceRedeployCotiExecutor && inboxCotiAddress) {
    logStep(`Redeploying COTI MpcExecutor (keeping inbox ${inboxCotiAddress})`);
    inboxCoti = await params.cotiViem.getContractAt("Inbox", inboxCotiAddress as `0x${string}`, {
      client: { public: cotiPublicClient, wallet: cotiWallet },
    });
    mpcExecutor = await params.cotiViem.deployContract(
      "MpcExecutor",
      [inboxCoti.address],
      {
        client: {
          public: cotiPublicClient,
          wallet: cotiWallet,
        },
      } as any
    );
    await writeCotiDeployments(cotiDeploymentsPath, {
      inbox: inboxCotiAddress,
      mpcExecutor: mpcExecutor.address,
    });
    logStep(`Saved updated MpcExecutor to ${cotiDeploymentsPath}`);
  } else {
    logStep("Deploying COTI Inbox + MpcExecutor");
    inboxCoti = await params.cotiViem.deployContract(
      "Inbox",
      [cotiChainId],
      {
        client: {
          public: cotiPublicClient,
          wallet: cotiWallet,
        },
      } as any
    );
    mpcExecutor = await params.cotiViem.deployContract(
      "MpcExecutor",
      [inboxCoti.address],
      {
        client: {
          public: cotiPublicClient,
          wallet: cotiWallet,
        },
      } as any
    );
    await writeCotiDeployments(cotiDeploymentsPath, {
      inbox: inboxCoti.address,
      mpcExecutor: mpcExecutor.address,
    });
    logStep(`Saved COTI deployments to ${cotiDeploymentsPath}`);
  }
  logStep(`COTI inbox address in use: ${inboxCoti.address}`);

  if (!reuseSepolia || !reuseCotiFull) {
    logStep("Configuring COTI executor + miner (pod test)");
    await podTest.write.configureCoti([mpcExecutor.address, cotiChainId]);
    const cotiOwner = await inboxCoti.read.owner();
    logStep(`COTI inbox owner ${cotiOwner}`);
    const alreadyMiner = await inboxCoti.read.isMiner([cotiWallet.account.address]);
    if (!alreadyMiner) {
      logStep(`Adding COTI miner ${cotiWallet.account.address}`);
      const addMinerTx = await inboxCoti.write.addMiner([cotiWallet.account.address], {
        account: cotiWallet.account,
      });
      await cotiPublicClient.waitForTransactionReceipt({ hash: addMinerTx, ...receiptWaitOptions });
      const confirmedMiner = await inboxCoti.read.isMiner([cotiWallet.account.address]);
      logStep(`COTI miner confirmed=${confirmedMiner}`);
    } else {
      logStep("COTI miner already configured");
    }
  } else {
    logStep("Skipping configureCoti/addMiner (reused Sepolia + full COTI cache)");
  }

  const sepoliaMiner = sepoliaWallet.account.address;
  const sepoliaAlreadyMiner = await inboxSepolia.read.isMiner([sepoliaMiner]);
  if (!sepoliaAlreadyMiner) {
    logStep(`Adding Sepolia miner ${sepoliaMiner}`);
    await inboxSepolia.write.addMiner([sepoliaMiner]);
  } else {
    logStep("Sepolia miner already configured");
  }

  const cotiRpcUrl = requireEnv("COTI_TESTNET_RPC_URL");
  const cotiProvider = new JsonRpcProvider(cotiRpcUrl) as any;
  const cotiPrivateKey = requirePrivateKey("COTI_TESTNET_PRIVATE_KEY");
  const onboardAddress = process.env.COTI_ONBOARD_CONTRACT_ADDRESS || ONBOARD_CONTRACT_ADDRESS;
  const userKey = await onboardUser(cotiPrivateKey, cotiRpcUrl, onboardAddress);
  const cotiEncryptWallet = new CotiWallet(cotiPrivateKey, cotiProvider as any);
  cotiEncryptWallet.setAesKey(userKey);

  logStep("Pod test setup complete");

  return {
    sepolia: { publicClient: sepoliaPublicClient, wallet: sepoliaWallet },
    coti: { publicClient: cotiPublicClient, wallet: cotiWallet },
    contracts: {
      inboxSepolia,
      inboxCoti,
      mpcExecutor,
      podTest,
      podTestAsCoti,
    },
    crypto: { userKey, cotiEncryptWallet },
    chainIds: { sepolia: sepoliaChainId, coti: cotiChainId },
    podContractName: params.podContractName,
  };
};

/**
 * `PodTest*.lastResult` may be returned as raw `abi.encode(...)` (32 / 64 / 128 bytes) or as a full
 * ABI-encoded Solidity `bytes` (offset + length + payload). Normalize to the inner payload for decoders.
 */
export const unwrapPodLastResultPayload = (getterHex: `0x${string}`): `0x${string}` => {
  const hex = (getterHex.startsWith("0x") ? getterHex : (`0x${getterHex}` as const)) as `0x${string}`;
  const byteLen = (hex.length - 2) / 2;
  if (byteLen === 32 || byteLen === 64 || byteLen === 128) {
    return hex;
  }
  try {
    const [inner] = decodeAbiParameters([{ type: "bytes", name: "payload" }], hex);
    return inner as `0x${string}`;
  } catch {
    return hex;
  }
};

/** Default gas for PodTest256 `exec*` on Hardhat (overridable via `MineRequestOptions.hardhatGas` or `POD_OPS_HARDHAT_GAS`). */
export const DEFAULT_POD_HARDHAT_GAS_256 = 30_000_000n;

/** Mine COTI + Sepolia round-trip for a pod exec tx; returns raw `lastResult` bytes (hex). */
export const runPodRoundTrip = async (
  ctx: PodTestContext,
  label: string,
  send: (podAsCoti: any, writeOpts?: { gas?: bigint }) => Promise<`0x${string}`>,
  mineOptions?: MineRequestOptions
): Promise<`0x${string}`> => {
  const hardhatGasFromEnv = process.env.POD_OPS_HARDHAT_GAS?.trim();
  const envHardhatGas = hardhatGasFromEnv ? BigInt(hardhatGasFromEnv) : undefined;
  const hardhatWriteGas =
    mineOptions?.hardhatGas ??
    envHardhatGas ??
    (ctx.podContractName === "PodTest256" ? DEFAULT_POD_HARDHAT_GAS_256 : undefined);
  const writeOpts = hardhatWriteGas !== undefined ? { gas: hardhatWriteGas } : undefined;
  const txHash = await send(ctx.contracts.podTestAsCoti, writeOpts);
  await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
  const request = await getLatestRequest(ctx.contracts.inboxSepolia);
  const defaultGas =
    ctx.podContractName === "PodTest256"
      ? DEFAULT_COTI_MINE_GAS_MPC_256
      : ctx.podContractName === "PodTest128"
        ? DEFAULT_COTI_MINE_GAS_MPC_128
        : undefined;
  const merged: MineRequestOptions | undefined =
    defaultGas !== undefined
      ? { ...mineOptions, gas: mineOptions?.gas ?? defaultGas }
      : mineOptions;
  const { requestIdUsed } = await mineRequest(
    ctx,
    "coti",
    BigInt(ctx.chainIds.sepolia),
    request,
    label,
    merged
  );
  const responseRequest = await getResponseRequestBySource(ctx.contracts.inboxCoti, requestIdUsed, label);
  // Pod tests use Hardhat as the "Sepolia" chain. EDR caps single-tx gas at 16777216; reusing COTI mine
  // gas (e.g. 50M for mul256) here makes `batchProcessRequests` fail before broadcast.
  const localMineOpts: MineRequestOptions | undefined =
    merged?.nonceOverride !== undefined ? { nonceOverride: merged.nonceOverride } : undefined;
  await mineRequest(ctx, "sepolia", ctx.chainIds.coti, responseRequest, label, localMineOpts);
  const getterHex = (await ctx.contracts.podTest.read.lastResult()) as `0x${string}`;
  return unwrapPodLastResultPayload(getterHex);
};

/** `abi.encode(ctUint64)` / `ctBool` payload: single uint256 word. */
export const decodePodCtUint64Word = (data: `0x${string}`): bigint => {
  const [v] = decodeAbiParameters([{ type: "uint256", name: "w" }], data);
  return v as bigint;
};

/** `abi.encode(uint256)` plaintext (e.g. executor `rand*` / `randBoundedBits*` responses). */
export const decodePodPlainUint256 = (data: `0x${string}`): bigint => {
  const [v] = decodeAbiParameters([{ type: "uint256", name: "v" }], data);
  return v as bigint;
};

/** Decode `abi.encode(ctUint128)` from executor respond payload. */
export const decodePodCtUint128Struct = (
  data: `0x${string}`
): { high: bigint; low: bigint } => {
  const [t] = decodeAbiParameters(
    [
      {
        type: "tuple",
        name: "ct",
        components: [
          { name: "high", type: "uint256" },
          { name: "low", type: "uint256" },
        ],
      },
    ],
    data
  );
  return t as { high: bigint; low: bigint };
};

/** Decode `abi.encode(ctUint256)` from executor respond payload. */
export const decodePodCtUint256Struct = (
  data: `0x${string}`
): { high: { high: bigint; low: bigint }; low: { high: bigint; low: bigint } } => {
  const [t] = decodeAbiParameters(
    [
      {
        type: "tuple",
        name: "ct",
        components: [
          {
            name: "high",
            type: "tuple",
            components: [
              { name: "high", type: "uint256" },
              { name: "low", type: "uint256" },
            ],
          },
          {
            name: "low",
            type: "tuple",
            components: [
              { name: "high", type: "uint256" },
              { name: "low", type: "uint256" },
            ],
          },
        ],
      },
    ],
    data
  );
  return t as {
    high: { high: bigint; low: bigint };
    low: { high: bigint; low: bigint };
  };
};

/**
 * Encrypt 0/1 using the same path as {@link buildEncryptedInput} (64-bit input text), validated on-chain as `itBool`.
 * `MpcExecutor.mux*` compensates so plaintext `1` still selects the first uint branch and `0` the second.
 */
export const buildEncryptedBool = async (ctx: MpcEncryptContext, bit: 0 | 1) =>
  buildEncryptedInput(ctx, BigInt(bit));

