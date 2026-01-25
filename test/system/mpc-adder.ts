import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { before, describe, it } from "node:test";
import { network } from "hardhat";
import {
  decodeAbiParameters,
  defineChain,
  encodeAbiParameters,
  encodeFunctionData,
  toFunctionSelector,
  toHex,
  zeroHash,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ONBOARD_CONTRACT_ADDRESS, Wallet as CotiWallet } from "@coti-io/coti-ethers";
import { decryptUint } from "@coti-io/coti-sdk-typescript";
import { Contract, JsonRpcProvider, Wallet } from "ethers";

const getTupleField = (value: any, key: string, index: number) => value?.[key] ?? value?.[index];

const requireEnv = (key: string) => {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing ${key} environment variable`);
  }
  return value;
};

const requirePrivateKey = (key: string) => {
  const value = process.env[key] ?? process.env.PRIVATE_KEY;
  if (!value) {
    throw new Error(`Missing ${key} or PRIVATE_KEY environment variable`);
  }
  return value;
};

const envOrEmpty = (key: string) => process.env[key]?.trim() ?? "";

const defaultBumpPercent = BigInt(parseInt(process.env.GAS_BUMP_PERCENT || "50"));
const replacementBumpPercent = BigInt(parseInt(process.env.GAS_REPLACEMENT_BUMP_PERCENT || "200"));
const bumpFee = (value: bigint, percent: bigint) => value + (value * percent) / 100n;

const buildFeeOverrides = (
  fees: {
  gasPrice?: bigint;
  maxFeePerGas?: bigint;
  maxPriorityFeePerGas?: bigint;
  },
  bumpPercent: bigint
) => {
  if (fees.gasPrice !== undefined) {
    return { gasPrice: bumpFee(fees.gasPrice, bumpPercent) };
  }
  const overrides: { maxFeePerGas?: bigint; maxPriorityFeePerGas?: bigint } = {};
  if (fees.maxFeePerGas !== undefined) {
    overrides.maxFeePerGas = bumpFee(fees.maxFeePerGas, bumpPercent);
  }
  if (fees.maxPriorityFeePerGas !== undefined) {
    overrides.maxPriorityFeePerGas = bumpFee(fees.maxPriorityFeePerGas, bumpPercent);
  }
  return overrides;
};

const logStep = (message: string) => {
  console.log(`[mpc-test] ${message}`);
};

const onboardUser = async (privateKey: string, rpcUrl: string, onboardAddress: string) => {
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

describe("MpcAdder (system)", async function () {
  const { viem: sepoliaViem } = await network.connect({ network: "hardhat" });
  const { viem: cotiViem } = await network.connect({ network: "cotiTestnet" });

  let sepoliaPublicClient: Awaited<ReturnType<typeof sepoliaViem.getPublicClient>>;
  let cotiPublicClient: Awaited<ReturnType<typeof cotiViem.getPublicClient>>;
  let sepoliaWallet: Awaited<ReturnType<typeof sepoliaViem.getWalletClients>>[number];
  let cotiWallet: Awaited<ReturnType<typeof cotiViem.getWalletClients>>[number];
  let hardhatCotiWallet: Awaited<ReturnType<typeof sepoliaViem.getWalletClient>>;

  let inboxSepolia: any;
  let inboxCoti: any;
  let mpcAdder: any;
  let mpcAdderAsCoti: any;
  let mpcExecutor: any;
  let userKey: string;
  let encryptionWallet: Wallet;
  let cotiEncryptWallet: CotiWallet;
  let functionSelector: `0x${string}`;
  let sepoliaFeeOverrides: { gasPrice?: bigint; maxFeePerGas?: bigint; maxPriorityFeePerGas?: bigint };
  let cotiFeeOverrides: { gasPrice?: bigint; maxFeePerGas?: bigint; maxPriorityFeePerGas?: bigint };
  let sepoliaNonce: number;
  let cotiNonce: number;
  let nextSepoliaOverrides: () => {
    gasPrice?: bigint;
    maxFeePerGas?: bigint;
    maxPriorityFeePerGas?: bigint;
  };
  let nextCotiOverrides: () => Promise<{
    gasPrice?: bigint;
    maxFeePerGas?: bigint;
    maxPriorityFeePerGas?: bigint;
    nonce: number;
  }>;
  const receiptWaitOptions = { timeout: 300_000, pollingInterval: 2_000 };

  const sepoliaChainId = parseInt(process.env.HARDHAT_CHAIN_ID || "31337");
  const cotiChainId = BigInt(parseInt(process.env.COTI_TESTNET_CHAIN_ID || "7082400"));
  const cotiDeploymentsPath =
    process.env.COTI_DEPLOYMENTS_PATH ||
    path.resolve(process.cwd(), "deployments", "coti-testnet.json");

  const readCotiDeployments = async () => {
    try {
      const raw = await fs.readFile(cotiDeploymentsPath, "utf8");
      return JSON.parse(raw) as { inbox?: string; mpcExecutor?: string };
    } catch {
      return {};
    }
  };

  const writeCotiDeployments = async (payload: { inbox: string; mpcExecutor: string }) => {
    await fs.mkdir(path.dirname(cotiDeploymentsPath), { recursive: true });
    const data = {
      ...payload,
      chainId: cotiChainId.toString(),
      updatedAt: new Date().toISOString(),
    };
    await fs.writeFile(cotiDeploymentsPath, JSON.stringify(data, null, 2));
  };


  before(async function () {
    requireEnv("COTI_TESTNET_RPC_URL");
    requirePrivateKey("COTI_TESTNET_PRIVATE_KEY");

    logStep("Preparing chain clients");
    const cotiChain = defineChain({
      id: Number(cotiChainId),
      name: "COTI Testnet",
      nativeCurrency: { name: "COTI", symbol: "COTI", decimals: 18 },
      rpcUrls: {
        default: { http: [requireEnv("COTI_TESTNET_RPC_URL")] },
      },
    });

    sepoliaPublicClient = await sepoliaViem.getPublicClient();
    cotiPublicClient = await cotiViem.getPublicClient({ chain: cotiChain });
    [sepoliaWallet] = await sepoliaViem.getWalletClients();
    const cotiAccount = privateKeyToAccount(
      `0x${requirePrivateKey("COTI_TESTNET_PRIVATE_KEY").replace(/^0x/, "")}` as `0x${string}`
    );
    hardhatCotiWallet = await sepoliaViem.getWalletClient(cotiAccount.address);
    cotiWallet = await cotiViem.getWalletClient(cotiAccount.address, { chain: cotiChain });

    logStep("Fetching nonces");
    sepoliaNonce = await sepoliaPublicClient.getTransactionCount({
      address: sepoliaWallet.account.address,
      blockTag: "latest",
    });
    const sepoliaPendingNonce = await sepoliaPublicClient.getTransactionCount({
      address: sepoliaWallet.account.address,
      blockTag: "pending",
    });
    cotiNonce = await cotiPublicClient.getTransactionCount({
      address: cotiWallet.account.address,
      blockTag: "latest",
    });
    const cotiPendingNonce = await cotiPublicClient.getTransactionCount({
      address: cotiWallet.account.address,
      blockTag: "pending",
    });

    const sepoliaBumpPercent =
      sepoliaPendingNonce > sepoliaNonce ? replacementBumpPercent : defaultBumpPercent;
    const cotiBumpPercent =
      cotiPendingNonce > cotiNonce ? replacementBumpPercent : defaultBumpPercent;

    logStep(
      `Nonces: sepolia latest=${sepoliaNonce} pending=${sepoliaPendingNonce}, coti latest=${cotiNonce} pending=${cotiPendingNonce}`
    );
    logStep(
      `Fee bump: sepolia=${sepoliaBumpPercent}% coti=${cotiBumpPercent}%`
    );

    logStep("Estimating fees");
    sepoliaFeeOverrides = buildFeeOverrides(
      { gasPrice: undefined,
        maxFeePerGas: 2000000000n,
        maxPriorityFeePerGas: 2000000000n,
      },
      // await sepoliaPublicClient.estimateFeesPerGas(),
      sepoliaBumpPercent
    );
    cotiFeeOverrides = buildFeeOverrides(
      await cotiPublicClient.estimateFeesPerGas(),
      cotiBumpPercent
    );

    nextSepoliaOverrides = () => ({ ...sepoliaFeeOverrides });
    nextCotiOverrides = async () => ({
      ...cotiFeeOverrides,
      nonce: await cotiPublicClient.getTransactionCount({
        address: cotiWallet.account.address,
        blockTag: "pending",
      }),
    });

    const inboxSepoliaAddress = envOrEmpty("HARDHAT_INBOX_ADDRESS") || envOrEmpty("SEPOLIA_INBOX_ADDRESS");
    const mpcAdderAddress =
      envOrEmpty("HARDHAT_MPC_ADDER_ADDRESS") || envOrEmpty("SEPOLIA_MPC_ADDER_ADDRESS");

    const cachedCoti = await readCotiDeployments();
    const inboxCotiAddress = envOrEmpty("COTI_INBOX_ADDRESS") || cachedCoti.inbox || "";
    const mpcExecutorAddress =
      envOrEmpty("COTI_MPC_EXECUTOR_ADDRESS") || cachedCoti.mpcExecutor || "";

    const reuseSepolia = inboxSepoliaAddress && mpcAdderAddress;
    const reuseCoti =
      envOrEmpty("COTI_REUSE_CONTRACTS").toLowerCase() === "true" &&
      inboxCotiAddress &&
      mpcExecutorAddress;

    if (reuseSepolia) {
      logStep(`Reusing Hardhat contracts: Inbox=${inboxSepoliaAddress} MpcAdder=${mpcAdderAddress}`);
      inboxSepolia = await sepoliaViem.getContractAt("Inbox", inboxSepoliaAddress as `0x${string}`);
      mpcAdder = await sepoliaViem.getContractAt("MpcAdder", mpcAdderAddress as `0x${string}`);
    } else {
      logStep("Deploying Hardhat Inbox + MpcAdder");
      inboxSepolia = await sepoliaViem.deployContract(
        "Inbox",
        [BigInt(sepoliaChainId)],
        { gasLimit: 5_000_000n } as any
      );
      mpcAdder = await sepoliaViem.deployContract("MpcAdder", [inboxSepolia.address], {
        gasLimit: 5_000_000n,
      } as any);
    }

    mpcAdderAsCoti = await sepoliaViem.getContractAt("MpcAdder", mpcAdder.address, {
      client: {
        public: sepoliaPublicClient,
        wallet: hardhatCotiWallet,
      },
    });

    if (reuseCoti) {
      logStep(`Reusing COTI contracts: Inbox=${inboxCotiAddress} MpcExecutor=${mpcExecutorAddress}`);
      inboxCoti = await cotiViem.getContractAt("Inbox", inboxCotiAddress as `0x${string}`, {
        client: { public: cotiPublicClient, wallet: cotiWallet },
      });
      mpcExecutor = await cotiViem.getContractAt(
        "MpcExecutor",
        mpcExecutorAddress as `0x${string}`,
        {
          client: { public: cotiPublicClient, wallet: cotiWallet },
        }
      );
    } else {
      logStep("Deploying COTI Inbox + MpcExecutor");
      inboxCoti = await cotiViem.deployContract(
        "Inbox",
        [cotiChainId],
        {
          ...(await nextCotiOverrides()),
          gasLimit: 5_000_000n,
          client: {
            public: cotiPublicClient,
            wallet: cotiWallet,
          },
        } as any
      );
      mpcExecutor = await cotiViem.deployContract(
        "MpcExecutor",
        [inboxCoti.address],
        {
          ...(await nextCotiOverrides()),
          gasLimit: 5_000_000n,
          client: {
            public: cotiPublicClient,
            wallet: cotiWallet,
          },
        } as any
      );
      await writeCotiDeployments({
        inbox: inboxCoti.address,
        mpcExecutor: mpcExecutor.address,
      });
      logStep(`Saved COTI deployments to ${cotiDeploymentsPath}`);
    }

    if (!reuseSepolia || !reuseCoti) {
      logStep("Configuring COTI executor + miner");
      await mpcAdder.write.configureCoti([mpcExecutor.address, cotiChainId], {
        ...nextSepoliaOverrides(),
      });
      const alreadyMiner = await inboxCoti.read.isMiner([cotiWallet.account.address]);
      if (!alreadyMiner) {
        await inboxCoti.write.addMiner([cotiWallet.account.address], { ...(await nextCotiOverrides()) });
      } else {
        logStep("COTI miner already configured");
      }
    } else {
      logStep("Skipping configureCoti/addMiner (reused contracts)");
    }

    const cotiRpcUrl = requireEnv("COTI_TESTNET_RPC_URL");
    const cotiProvider = new JsonRpcProvider(cotiRpcUrl) as any;
    const cotiPrivateKey = requirePrivateKey("COTI_TESTNET_PRIVATE_KEY");
    encryptionWallet = new Wallet(cotiPrivateKey, cotiProvider);
    const onboardAddress =
      process.env.COTI_ONBOARD_CONTRACT_ADDRESS || ONBOARD_CONTRACT_ADDRESS;
    userKey = await onboardUser(cotiPrivateKey, cotiRpcUrl, onboardAddress);
    cotiEncryptWallet = new CotiWallet(cotiPrivateKey, cotiProvider as any);
    cotiEncryptWallet.setAesKey(userKey);

    functionSelector = toFunctionSelector(
      "batchProcessRequests(uint256,(bytes32,address,address,(bytes4,bytes,bytes8[],bytes32[]),bytes4,bytes4,bool,bytes32)[],(bytes32,uint64,bytes)[])"
    );
    logStep("Setup complete");
  });

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

  const buildEncryptedInput = async (
    value: bigint
  ): Promise<{ ciphertext: bigint; signature: `0x${string}` }> => {
    const inputText = await cotiEncryptWallet.encryptValue(value, inboxCoti.address, functionSelector);
    const ciphertext = normalizeCiphertext(inputText.ciphertext);
    return {
      ciphertext,
      signature: toHex(inputText.signature as any),
    };
  };

  it.skip("Should create an outgoing MPC request from Sepolia", async function () {
    const a = 12n;
    const b = 30n;

    logStep("Test1: encrypt inputs");
    const fromBlock = await sepoliaPublicClient.getBlockNumber();
    const itA = await buildEncryptedInput(a);
    const itB = await buildEncryptedInput(b);
    logStep("Test1: sending add()");
    const txHash = await mpcAdderAsCoti.write.add([itA, itB], nextSepoliaOverrides());
    logStep(`Test1: waiting for tx ${txHash}`);
    await sepoliaPublicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    logStep("Test1: tx confirmed, fetching MessageSent");

    const events = (await sepoliaPublicClient.getContractEvents({
      address: inboxSepolia.address,
      abi: inboxSepolia.abi,
      eventName: "MessageSent",
      fromBlock,
      strict: true,
    })) as any[];

    logStep(`Test1: MessageSent events=${events.length}`);
    assert.ok(events.length > 0);
    const messageEvent = events[events.length - 1];
    const requestId = messageEvent.args.requestId!;

    const expectedSelector = toFunctionSelector("add(uint256,uint256,address)");
    const encodedA = encodeAbiParameters(
      [
        {
          type: "tuple",
          components: [
            { name: "ciphertext", type: "uint256" },
            { name: "signature", type: "bytes" },
          ],
        },
      ],
      [itA]
    );
    const encodedB = encodeAbiParameters(
      [
        {
          type: "tuple",
          components: [
            { name: "ciphertext", type: "uint256" },
            { name: "signature", type: "bytes" },
          ],
        },
      ],
      [itB]
    );
    const encodedOwner = encodeAbiParameters(
      [{ type: "address" }],
      [sepoliaWallet.account.address]
    );
    const expectedArgsData = `0x${encodedA.slice(2)}${encodedB.slice(2)}${encodedOwner.slice(2)}`;

    const request = await inboxSepolia.read.requests([requestId]);
    logStep("Test1: loaded request from hardhat inbox");
    const targetChainId = getTupleField(request, "targetChainId", 1);
    const targetContract = getTupleField(request, "targetContract", 2);
    const callerContract = getTupleField(request, "callerContract", 4);
    const originalSender = getTupleField(request, "originalSender", 5);
    const requestMethodCall = getTupleField(request, "methodCall", 3);
    const requestSelector = getTupleField(requestMethodCall, "selector", 0);
    const requestData = getTupleField(requestMethodCall, "data", 1);
    const isTwoWay = getTupleField(request, "isTwoWay", 9);
    const executed = getTupleField(request, "executed", 10);
    const sourceRequestId = getTupleField(request, "sourceRequestId", 11);

    assert.equal(Number(targetChainId), Number(cotiChainId));
    assert.equal(targetContract.toLowerCase(), mpcExecutor.address.toLowerCase());
    assert.equal(callerContract.toLowerCase(), mpcAdder.address.toLowerCase());
    assert.equal(originalSender.toLowerCase(), mpcAdder.address.toLowerCase());
    assert.equal(requestSelector, expectedSelector);
    assert.equal(requestData, expectedArgsData);
    assert.equal(isTwoWay, true);
    assert.equal(executed, false);
    assert.equal(sourceRequestId, zeroHash);

    assert.equal(Number(messageEvent.args.targetChainId), Number(cotiChainId));
    assert.equal(messageEvent.args.targetContract?.toLowerCase(), mpcExecutor.address.toLowerCase());
    const eventMethodCall = messageEvent.args.methodCall;
    assert.equal(eventMethodCall.selector, expectedSelector);
    assert.equal(eventMethodCall.data, expectedArgsData);
    assert.equal(messageEvent.args.callbackSelector, toFunctionSelector("receiveC(bytes)"));
    assert.equal(messageEvent.args.errorSelector, toFunctionSelector("onDefaultMpcError(bytes32)"));
  });

  it.only("Should execute the MPC request on COTI and create a response", async function () {
    const a = 7n;
    const b = 9n;

    logStep("Test2: encrypt inputs");
    const fromBlock = await sepoliaPublicClient.getBlockNumber();
    const itA = await buildEncryptedInput(a);
    const itB = await buildEncryptedInput(b);
    logStep("Test2: sending add()");
    const txHash = await mpcAdderAsCoti.write.add([itA, itB], nextSepoliaOverrides());
    logStep(`Test2: waiting for tx ${txHash}`);
    await sepoliaPublicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    logStep("Test2: tx confirmed, processing on COTI");

    const events = (await sepoliaPublicClient.getContractEvents({
      address: inboxSepolia.address,
      abi: inboxSepolia.abi,
      eventName: "MessageSent",
      fromBlock,
      strict: true,
    })) as any[];

    const messageEvent = events[events.length - 1];
    const requestId = messageEvent.args.requestId!;
    const methodCall = messageEvent.args.methodCall;
    const callbackSelector = messageEvent.args.callbackSelector ?? "0x00000000";
    const errorSelector = messageEvent.args.errorSelector ?? "0x00000000";
    assert.ok(methodCall);

    logStep("Test2: calling batchProcessRequests on COTI");
    const processTxHash = await inboxCoti.write.batchProcessRequests([
      BigInt(sepoliaChainId),
      [
        {
          requestId,
          sourceContract: mpcAdder.address,
          targetContract: mpcExecutor.address,
          methodCall,
          callbackSelector,
          errorSelector,
          isTwoWay: true,
          sourceRequestId: zeroHash,
        },
      ],
      [],
    ], await nextCotiOverrides());
    logStep(`Test2: waiting for COTI tx ${processTxHash}`);
    await cotiPublicClient.waitForTransactionReceipt({ hash: processTxHash, ...receiptWaitOptions });
    logStep("Test2: COTI processed, fetching response");

    const incoming = await inboxCoti.read.incomingRequests([requestId]);
    logStep("Test2: loaded incoming request on COTI");
    const incomingTargetChainId = getTupleField(incoming, "targetChainId", 1);
    const incomingExecuted = getTupleField(incoming, "executed", 10);

    let response: any;
    try {
      response = await inboxCoti.read.getInboxResponse([requestId]);
      logStep("Test2: loaded inbox response on COTI");
    } catch (error) {
      const inboxError = await inboxCoti.read.errors([requestId]);
      const errorCode = getTupleField(inboxError, "errorCode", 1);
      const errorMessage = getTupleField(inboxError, "errorMessage", 2);
      logStep(`Test2: no response, errorCode=${errorCode} errorMessage=${errorMessage}`);
      throw error;
    }
    assert.ok(response);

    const responseCount = await inboxCoti.read.getRequestsLen();
    logStep(`Test2: response requests count=${responseCount}`);
    assert.ok(Number(responseCount) > 0);
    const responseRequests = await inboxCoti.read.getRequests([0, responseCount]);
    logStep("Test2: fetched response requests list");

    const responseRequest = (responseRequests as any[]).find(
      (req) => getTupleField(req, "sourceRequestId", 11) === requestId
    );
    assert.ok(responseRequest);

    const responseRequestId = getTupleField(responseRequest, "requestId", 0);
    const responseTargetChainId = getTupleField(responseRequest, "targetChainId", 1);
    const responseTargetContract = getTupleField(responseRequest, "targetContract", 2);
    const responseMethodCall = getTupleField(responseRequest, "methodCall", 3);
    const responseSelector = getTupleField(responseMethodCall, "selector", 0);
    const responseData = getTupleField(responseMethodCall, "data", 1);
    const responseSourceContract = getTupleField(responseRequest, "originalSender", 5);
    const responseCallbackSelector = getTupleField(responseRequest, "callbackSelector", 7) ?? "0x00000000";
    const responseErrorSelector = getTupleField(responseRequest, "errorSelector", 8) ?? "0x00000000";
    const responseIsTwoWay = getTupleField(responseRequest, "isTwoWay", 9);
    const responseSourceRequestId = getTupleField(responseRequest, "sourceRequestId", 11);

    assert.ok(responseRequestId);
    assert.ok(responseTargetContract);
    assert.ok(responseSourceContract);
    assert.ok(responseData);
    assert.ok(responseSelector);

    assert.equal(Number(responseTargetChainId), sepoliaChainId);
    assert.equal(responseTargetContract.toLowerCase(), mpcAdder.address.toLowerCase());
    assert.equal(responseIsTwoWay, false);
    assert.equal(responseSourceRequestId, requestId);
    assert.equal(responseCallbackSelector, "0x00000000");
    assert.equal(responseErrorSelector, toFunctionSelector("onDefaultMpcError(bytes32)"));

    assert.equal(responseSelector, "0x00000000");
    const respondSelector = toFunctionSelector("respond(bytes)");
    const responseDataHex = responseData as `0x${string}`;
    assert.ok(responseDataHex.startsWith(respondSelector));
    const expectedResponseData = `${respondSelector}${response.slice(2)}`.toLowerCase();
    assert.equal(responseDataHex.toLowerCase(), expectedResponseData);
    const [decodedCiphertext] = decodeAbiParameters([{ type: "uint256" }], response);
    assert.ok(decodedCiphertext);

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
      args: [response],
    });
    const applyMethodCall = {
      selector: "0x00000000",
      data: receiveCData,
      datatypes: [],
      datalens: [],
    };

    logStep("Test2: applying response on hardhat inbox");
    await inboxSepolia.write.batchProcessRequests([
      cotiChainId,
      [
        {
          requestId: responseRequestId,
          sourceContract: responseSourceContract,
          targetContract: responseTargetContract,
          methodCall: applyMethodCall,
          callbackSelector: responseCallbackSelector,
          errorSelector: responseErrorSelector,
          isTwoWay: false,
          sourceRequestId: responseSourceRequestId,
        },
      ],
      [],
    ], nextSepoliaOverrides());
    logStep("Test2: response applied on hardhat");
  });

  it("Should decrypt the MPC result on Sepolia", async function () {
    const a = 15n;
    const b = 27n;

    logStep("Test3: encrypt inputs");
    const fromBlock = await sepoliaPublicClient.getBlockNumber();
    const itA = await buildEncryptedInput(a);
    const itB = await buildEncryptedInput(b);
    logStep("Test3: sending add()");
    const txHash = await mpcAdderAsCoti.write.add([itA, itB], nextSepoliaOverrides());
    logStep(`Test3: waiting for tx ${txHash}`);
    await sepoliaPublicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    logStep("Test3: tx confirmed, processing on COTI");

    const events = (await sepoliaPublicClient.getContractEvents({
      address: inboxSepolia.address,
      abi: inboxSepolia.abi,
      eventName: "MessageSent",
      fromBlock,
      strict: true,
    })) as any[];

    const messageEvent = events[events.length - 1];
    const requestId = messageEvent.args.requestId!;
    const methodCall = messageEvent.args.methodCall;
    const callbackSelector = messageEvent.args.callbackSelector ?? "0x00000000";
    const errorSelector = messageEvent.args.errorSelector ?? "0x00000000";
    assert.ok(methodCall);

    logStep("Test3: calling batchProcessRequests on COTI");
    const processTxHash = await inboxCoti.write.batchProcessRequests([
      BigInt(sepoliaChainId),
      [
        {
          requestId,
          sourceContract: mpcAdder.address,
          targetContract: mpcExecutor.address,
          methodCall,
          callbackSelector,
          errorSelector,
          isTwoWay: true,
          sourceRequestId: zeroHash,
        },
      ],
      [],
    ], await nextCotiOverrides());
    logStep(`Test3: waiting for COTI tx ${processTxHash}`);
    await cotiPublicClient.waitForTransactionReceipt({ hash: processTxHash, ...receiptWaitOptions });
    logStep("Test3: COTI processed, applying response on hardhat");

    const responseCount = await inboxCoti.read.getRequestsLen();
    logStep(`Test3: response requests count=${responseCount}`);
    assert.ok(Number(responseCount) > 0);
    const responseRequests = await inboxCoti.read.getRequests([0, responseCount]);
    logStep("Test3: fetched response requests list");
    const responseRequest = (responseRequests as any[]).find(
      (req) => getTupleField(req, "sourceRequestId", 11) === requestId
    );
    assert.ok(responseRequest);

    const responseRequestId = getTupleField(responseRequest, "requestId", 0);
    const responseTargetContract = getTupleField(responseRequest, "targetContract", 2);
    const responseMethodCall = getTupleField(responseRequest, "methodCall", 3);
    const responseSourceContract = getTupleField(responseRequest, "originalSender", 5);
    const responseCallbackSelector = getTupleField(responseRequest, "callbackSelector", 7) ?? "0x00000000";
    const responseErrorSelector = getTupleField(responseRequest, "errorSelector", 8) ?? "0x00000000";
    const responseSourceRequestId = getTupleField(responseRequest, "sourceRequestId", 11);
    const response = await inboxCoti.read.getInboxResponse([requestId]);

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
      args: [response],
    });
    const applyMethodCall = {
      selector: "0x00000000",
      data: receiveCData,
      datatypes: [],
      datalens: [],
    };

    logStep("Test3: applying response on hardhat inbox");
    await inboxSepolia.write.batchProcessRequests([
      cotiChainId,
      [
        {
          requestId: responseRequestId,
          sourceContract: responseSourceContract,
          targetContract: responseTargetContract,
          methodCall: applyMethodCall,
          callbackSelector: responseCallbackSelector,
          errorSelector: responseErrorSelector,
          isTwoWay: false,
          sourceRequestId: responseSourceRequestId,
        },
      ],
      [],
    ], nextSepoliaOverrides());
    logStep("Test3: response applied, decrypting result");

    const encryptedResult = await mpcAdder.read.resultCiphertext();
    const ciphertext =
      getTupleField(encryptedResult, "ciphertext", 0) ??
      getTupleField(encryptedResult, "value", 0) ??
      encryptedResult;

    const decrypted = decryptUint(ciphertext, userKey);
    assert.equal(decrypted, a + b);
  });
});

