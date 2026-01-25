import assert from "node:assert/strict";
import { before, describe, it } from "node:test";
import { network } from "hardhat";
import { decodeAbiParameters, defineChain, toFunctionSelector, toHex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ONBOARD_CONTRACT_ADDRESS, Wallet as CotiWallet } from "@coti-io/coti-ethers";
import { decryptUint } from "@coti-io/coti-sdk-typescript";
import { JsonRpcProvider, Wallet } from "ethers";

const logStep = (message: string) => {
  console.log(`[mpc-test] ${message}`);
};

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
    key = key.slice(0, 32);
  }
  logStep("Onboarding complete");
  return key;
};

describe("MpcExecutor (mock inbox)", async function () {
  const { viem: cotiViem } = await network.connect({ network: "cotiTestnet" });

  let cotiPublicClient: Awaited<ReturnType<typeof cotiViem.getPublicClient>>;
  let cotiWallet: Awaited<ReturnType<typeof cotiViem.getWalletClient>>;
  let mpcExecutor: any;
  let mockInbox: any;
  let userKey: string;
  let encryptionWallet: Wallet;
  let cotiEncryptWallet: CotiWallet;
  let functionSelector: `0x${string}`;

  const cotiChainId = BigInt(parseInt(process.env.COTI_TESTNET_CHAIN_ID || "7082400"));
  const receiptWaitOptions = { timeout: 300_000, pollingInterval: 2_000 };

  before(async function () {
    requireEnv("COTI_TESTNET_RPC_URL");
    requirePrivateKey("COTI_TESTNET_PRIVATE_KEY");

    const cotiRpcUrl = requireEnv("COTI_TESTNET_RPC_URL");
    const cotiChain = defineChain({
      id: Number(cotiChainId),
      name: "COTI Testnet",
      nativeCurrency: { name: "COTI", symbol: "COTI", decimals: 18 },
      rpcUrls: { default: { http: [cotiRpcUrl] } },
    });

    cotiPublicClient = await cotiViem.getPublicClient({ chain: cotiChain });
    const cotiPrivateKey = requirePrivateKey("COTI_TESTNET_PRIVATE_KEY");
    const cotiAccount = privateKeyToAccount(
      `0x${cotiPrivateKey.replace(/^0x/, "")}` as `0x${string}`
    );
    cotiWallet = await cotiViem.getWalletClient(cotiAccount.address, { chain: cotiChain });
    const rpcProvider = new JsonRpcProvider(cotiRpcUrl) as any;
    encryptionWallet = new Wallet(cotiPrivateKey, rpcProvider);
    cotiEncryptWallet = new CotiWallet(cotiPrivateKey, rpcProvider);
    const onboardAddress = process.env.COTI_ONBOARD_CONTRACT_ADDRESS || ONBOARD_CONTRACT_ADDRESS;
    userKey = await onboardUser(cotiPrivateKey, cotiRpcUrl, onboardAddress);
    cotiEncryptWallet.setAesKey(userKey);

    logStep("Deploying MockInbox + MpcExecutor");
    mockInbox = await cotiViem.deployContract(
      "MockInbox",
      [],
      { gasLimit: 5_000_000n, client: { public: cotiPublicClient, wallet: cotiWallet } } as any
    );
    mpcExecutor = await cotiViem.deployContract("MpcExecutor", [mockInbox.address], {
      gasLimit: 5_000_000n,
      client: { public: cotiPublicClient, wallet: cotiWallet },
    } as any);

    functionSelector = toFunctionSelector("triggerValidate((uint256,bytes))");
  });

  const buildEncryptedInput = async (value: bigint) => {
    const inputText = await cotiEncryptWallet.encryptValue(value, mpcExecutor.address, functionSelector);
    return {
      ciphertext: inputText.ciphertext,
      signature: toHex(inputText.signature as any),
    };
  };

  it("Should validate ciphertext and return encrypted result via MockInbox", async function () {
    const value = 11n;
    const itValue = await buildEncryptedInput(value);

    logStep("Calling simplyValidate via MockInbox");
    const txHash = await mockInbox.write.triggerValidate([mpcExecutor.address, itValue]);
    await cotiPublicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });

    const response = await mockInbox.read.lastResponse();
    if (response === "0x") {
      const lastError = await mockInbox.read.lastError();
      const lastSuccess = await mockInbox.read.lastSuccess();
      logStep(`MockInbox lastSuccess=${lastSuccess} lastError=${lastError}`);
    }
    assert.notEqual(response, "0x");
    const [ct] = decodeAbiParameters([{ type: "uint256" }], response);
    const decrypted = decryptUint(ct, userKey);
    assert.equal(decrypted, value);
  });
});

