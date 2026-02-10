import assert from "node:assert/strict";
import { before, describe, it } from "node:test";
import { network } from "hardhat";
import { decryptUint } from "@coti-io/coti-sdk-typescript";
import { privateKeyToAccount } from "viem/accounts";
import { createWalletClient, custom, parseEther } from "viem";
import {
  buildEncryptedInput,
  envOrEmpty,
  getRequests,
  getResponseRequestBySource,
  getTupleField,
  logStep,
  mineRequest,
  normalizePrivateKey,
  requirePrivateKey,
  receiptWaitOptions,
  setupContext,
  type TestContext,
  getCotiCrypto,
} from "./mpc-test-utils.js";

describe("Millionaire (system)", async function () {
  const { viem: sepoliaViem } = await network.connect({ network: "hardhat" });
  const { viem: cotiViem } = await network.connect({ network: "cotiTestnet" });

  let ctx: TestContext;
  let walletA: any;
  let walletB: any;
  let userKeyB = "";

  const decodeCtBool = (value: unknown): bigint => {
    return (
      getTupleField(value, "ciphertext", 0) ??
      getTupleField(value, "value", 0) ??
      (value as bigint)
    );
  };

  before(async function () {
    // Deploy fresh COTI contracts for clean nonces.
    process.env.COTI_REUSE_CONTRACTS = "false";
    ctx = await setupContext({ sepoliaViem, cotiViem });

    const cotiKeyB =
      envOrEmpty("COTI_TESTNET_PRIVATE_KEY_B") || requirePrivateKey("PRIVATE_KEY_ACCOUNT_2");
    userKeyB = (await getCotiCrypto(
      cotiKeyB,
      process.env.COTI_TESTNET_RPC_URL || "",
      "USER_AES_KEY_2"
    )).userKey;

    const transport = custom({
      request: (args) => ctx.sepolia.publicClient.request(args),
    });
    const [funder] = await sepoliaViem.getWalletClients();
    const ensureFunds = async (address: `0x${string}`) => {
      const balance = await ctx.sepolia.publicClient.getBalance({ address });
      if (balance < parseEther("0.1")) {
        await funder.sendTransaction({ to: address, value: parseEther("1") });
      }
    };

    const accountA = privateKeyToAccount(
      normalizePrivateKey(requirePrivateKey("COTI_TESTNET_PRIVATE_KEY")) as `0x${string}`
    );
    const accountB = privateKeyToAccount(normalizePrivateKey(cotiKeyB) as `0x${string}`);

    await ensureFunds(accountA.address);
    await ensureFunds(accountB.address);

    walletA = createWalletClient({
      account: accountA,
      chain: ctx.sepolia.publicClient.chain,
      transport,
    });
    walletB = createWalletClient({
      account: accountB,
      chain: ctx.sepolia.publicClient.chain,
      transport,
    });
  });

  const deployMillionaire = async () => {
    const deployed = await sepoliaViem.deployContract("Millionaire", [ctx.contracts.inboxSepolia.address]);
    const millionaire = await sepoliaViem.getContractAt("Millionaire", deployed.address, {
      client: { public: ctx.sepolia.publicClient, wallet: walletA },
    });
    const millionaireAsB = await sepoliaViem.getContractAt("Millionaire", deployed.address, {
      client: { public: ctx.sepolia.publicClient, wallet: walletB },
    });
    await millionaire.write.configureCoti([ctx.contracts.mpcExecutor.address, ctx.chainIds.coti]);
    return { millionaire, millionaireAsB };
  };

  const runCase = async (label: string, wealthA: bigint, wealthB: bigint, expectAGtB: boolean) => {
    const { millionaire, millionaireAsB } = await deployMillionaire();

    logStep(`${label}: encrypt inputs`);
    const itA = await buildEncryptedInput(ctx, wealthA);
    const itB = await buildEncryptedInput(ctx, wealthB);

    logStep(`${label}: register wealth A`);
    let txHash = await millionaire.write.registerMyWealth([itA]);
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });

    logStep(`${label}: register wealth B`);
    txHash = await millionaireAsB.write.registerMyWealth([itB], { account: walletB.account });
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });

    logStep(`${label}: check reveal not possible yet`);
    const [existsBeforeA] = await millionaire.read.revealMyWealthGtThan(
      [walletB.account.address],
      { account: walletA.account.address }
    );
    const [existsBeforeB] = await millionaireAsB.read.revealMyWealthGtThan([walletA.account.address]);
    assert.equal(existsBeforeA, false);
    assert.equal(existsBeforeB, false);

    const countBefore = await ctx.contracts.inboxSepolia.read.getRequestsLen();
    logStep(`${label}: sending reveal`);
    txHash = await millionaire.write.reveal([walletA.account.address, walletB.account.address]);
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    const countAfter = await ctx.contracts.inboxSepolia.read.getRequestsLen();
    assert.equal(Number(countAfter), Number(countBefore) + 2);

    const newRequests = await getRequests(ctx.contracts.inboxSepolia, Number(countBefore), 2);
    assert.equal(newRequests.length, 2);

    logStep(`${label}: mining 2 requests on COTI`);
    for (let i = 0; i < newRequests.length; i += 1) {
      const request = newRequests[i];
      const stepLabel = `${label}-req${i + 1}`;
      await mineRequest(ctx, "coti", BigInt(ctx.chainIds.sepolia), request, stepLabel);
      const responseRequest = await getResponseRequestBySource(ctx.contracts.inboxCoti, request.requestId, stepLabel);
      await mineRequest(ctx, "sepolia", ctx.chainIds.coti, responseRequest, stepLabel);
    }

    logStep(`${label}: verifying reveal result`);
    const [existsA, ctBoolA] = await millionaire.read.revealMyWealthGtThan(
      [walletB.account.address],
      { account: walletA.account.address }
    );
    const [existsB, ctBoolB] = await millionaireAsB.read.revealMyWealthGtThan(
      [walletA.account.address],
      { account: walletB.account.address }
    );
    assert.equal(existsA, true);
    assert.equal(existsB, true);
    const decryptedA = decryptUint(decodeCtBool(ctBoolA), ctx.crypto.userKey);
    const decryptedB = decryptUint(decodeCtBool(ctBoolB), userKeyB);
    logStep(
      `${label}: existsA=${existsA} existsB=${existsB} decryptedA=${decryptedA.toString()} decryptedB=${decryptedB.toString()}`
    );
    const isTrueA = decryptedA !== 0n;
    const isTrueB = decryptedB !== 0n;
    logStep(`${label}: isTrueA=${isTrueA} isTrueB=${isTrueB} expectAGtB=${expectAGtB}`);
    assert.equal(isTrueA, expectAGtB);
    assert.equal(isTrueB, !expectAGtB);
  };

  it("Should reveal A greater-than B for multiple cases", async function () {
    await runCase("Case1", 50n, 10n, true);
    await runCase("Case2", 10n, 50n, false);
  });
});
