import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { defineChain, encodeFunctionData, toFunctionSelector, toHex } from "viem";
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

// Returns a trimmed environment variable or empty string.
export const envOrEmpty = (key: string) => process.env[key]?.trim() ?? "";

// Writes step logs with a common prefix.
export const logStep = (message: string) => {
  console.log(`[mpc-test] ${message}`);
};

// Returns a receipt wait config with consistent polling.
export const receiptWaitOptions = { timeout: 300_000, pollingInterval: 2_000 };

// Onboards a user on COTI and returns the AES key.
export const onboardUser = async (privateKey: string, rpcUrl: string, onboardAddress: string) => {
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
  return key;
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

// Mines a source request on the COTI inbox and waits for confirmation.
export const mineRequest = async (
  ctx: TestContext,
  chain: "coti" | "sepolia",
  sourceChainId: bigint,
  request: Request,
  label: string
): Promise<`0x${string}`> => {
  const inbox = chain === "coti" ? ctx.contracts.inboxCoti : ctx.contracts.inboxSepolia;
  const publicClient = chain === "coti" ? ctx.coti.publicClient : ctx.sepolia.publicClient;
  const chainLabel = chain.toUpperCase();
  logStep(`${label}: calling batchProcessRequests on ${chainLabel}`);
  const txHash = await inbox.write.batchProcessRequests([
    sourceChainId,
    [
      {
        requestId: request.requestId,
        sourceContract: request.originalSender,
        targetContract: request.targetContract,
        methodCall: request.methodCall,
        callbackSelector: request.callbackSelector ?? "0x00000000",
        errorSelector: request.errorSelector ?? "0x00000000",
        isTwoWay: request.isTwoWay,
        sourceRequestId: request.sourceRequestId,
      },
    ],
    [],
  ]);
  logStep(`${label}: waiting for ${chainLabel} tx ${txHash}`);
  await publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
  return txHash;
};

// Loads the response request linked to a source request id.
export const getResponseRequestBySource = async (
  inboxCoti: any,
  sourceRequestId: `0x${string}`,
  label: string
): Promise<Request> => {
  const rawResponse = await inboxCoti.read.inboxResponses([sourceRequestId]);
  const responseRequestId = getTupleField(rawResponse, "responseRequestId", 0) as `0x${string}`;
  assert.ok(
    responseRequestId &&
      responseRequestId !== "0x0000000000000000000000000000000000000000000000000000000000000000"
  );
  logStep(`${label}: responseRequestId=${responseRequestId}`);

  const rawRequest = await inboxCoti.read.requests([responseRequestId]);
  const responseRequest = parseRequest(rawRequest);
  assert.ok(responseRequest);
  return responseRequest;
};

// Encrypts an input value using the COTI wallet.
export const buildEncryptedInput = async (
  ctx: TestContext,
  value: bigint
): Promise<{ ciphertext: bigint; signature: `0x${string}` }> => {
  const functionSelector = toFunctionSelector(
      "batchProcessRequests(uint256,(bytes32,address,address,(bytes4,bytes,bytes8[],bytes32[]),bytes4,bytes4,bool,bytes32)[],(bytes32,uint64,bytes)[])"
  );
  const inputText = await ctx.crypto.cotiEncryptWallet.encryptValue(
    value,
    ctx.contracts.inboxCoti.address,
    functionSelector
  );
  const ciphertext = normalizeCiphertext(inputText.ciphertext);
  return {
    ciphertext,
    signature: toHex(inputText.signature as any),
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
  const cotiAccount = privateKeyToAccount(
    `0x${requirePrivateKey("COTI_TESTNET_PRIVATE_KEY").replace(/^0x/, "")}` as `0x${string}`
  );
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

  if (!reuseSepolia || !reuseCoti) {
    logStep("Configuring COTI executor + miner");
    await mpcAdder.write.configureCoti([mpcExecutor.address, cotiChainId]);
    const alreadyMiner = await inboxCoti.read.isMiner([cotiWallet.account.address]);
    if (!alreadyMiner) {
      await inboxCoti.write.addMiner([cotiWallet.account.address]);
    } else {
      logStep("COTI miner already configured");
    }
  } else {
    logStep("Skipping configureCoti/addMiner (reused contracts)");
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

// Normalizes ciphertext into a bigint for MPC encoding.
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

