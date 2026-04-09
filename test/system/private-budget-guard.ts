import assert from "node:assert/strict";
import { afterEach, before, describe, it } from "node:test";
import { network } from "hardhat";
import { decryptUint } from "@coti-io/coti-sdk-typescript";
import { privateKeyToAccount } from "viem/accounts";
import { createWalletClient, custom, parseEther } from "viem";
import {
  buildEncryptedInput,
  collectInboxFeesAfterTest,
  getCotiCrypto,
  getTupleField,
  logStep,
  normalizePrivateKey,
  podTwoWayWriteOptions,
  receiptWaitOptions,
  requirePrivateKey,
  runCrossChainTwoWayRoundTrip,
  setupContext,
  type TestContext,
} from "./mpc-test-utils.js";
import { podConfigureKeepInbox } from "../../scripts/deploy-utils.js";

const EXPLICIT_SECOND_COTI_KEY =
  process.env.COTI_TESTNET_PRIVATE_KEY_B?.trim() || process.env.PRIVATE_KEY_ACCOUNT_2?.trim() || "";
const EXPLICIT_COTI_SYSTEM_KEY = process.env.COTI_SYSTEM_PRIVATE_KEY?.trim() || "";
const ZERO_REQUEST_ID = `0x${"0".repeat(64)}` as const;

describe("PrivateBudgetGuard (system)", async function () {
  const { viem: sepoliaViem } = await network.connect({ network: "hardhat" });
  const { viem: cotiViem } = await network.connect({ network: "cotiTestnet" });

  let ctx: TestContext;
  let walletA: any;
  let walletB: any;
  let cryptoB: { cotiEncryptWallet: any; userKey: string } | undefined;
  let inputSignerCrypto: { cotiEncryptWallet: any; userKey: string };

  afterEach(async function () {
    if (ctx) await collectInboxFeesAfterTest(ctx);
  });

  const decodeCipherWord = (value: unknown): bigint => {
    return (
      getTupleField(value, "ciphertext", 0) ??
      getTupleField(value, "value", 0) ??
      (value as bigint)
    );
  };

  const decryptCtBool = (value: unknown, userKey: string) => decryptUint(decodeCipherWord(value), userKey) !== 0n;
  const decryptCtUint64 = (value: unknown, userKey: string) => decryptUint(decodeCipherWord(value), userKey);
  const expectReject = async (action: () => Promise<unknown>, expectedNeedle: string) => {
    await assert.rejects(action, (error: unknown) => {
      const message = error instanceof Error ? error.message : String(error);
      return message.includes(expectedNeedle);
    });
  };

  // In this harness, MPC input ciphertexts are produced by a single COTI-side signer.
  // Set `COTI_SYSTEM_PRIVATE_KEY` to make that explicit; otherwise we fall back to user A's key.
  const encryptFor = async (encryptWallet: any, value: bigint) =>
    buildEncryptedInput(
      {
        crypto: { userKey: "", cotiEncryptWallet: encryptWallet },
        contracts: { inboxCoti: { address: ctx.contracts.inboxCoti.address as `0x${string}` } },
      },
      value
    );

  const deployBudgetGuard = async (remoteContractName: "PrivateBudgetGuardCoti" | "PrivateBudgetGuardCotiFailureHarness" = "PrivateBudgetGuardCoti") => {
    const deployed = await sepoliaViem.deployContract("PrivateBudgetGuard", [ctx.contracts.inboxSepolia.address], {
      client: { public: ctx.sepolia.publicClient, wallet: walletA },
    });
    const budgetGuard = await sepoliaViem.getContractAt("PrivateBudgetGuard", deployed.address, {
      client: { public: ctx.sepolia.publicClient, wallet: walletA },
    });
    const budgetGuardAsB = walletB
      ? await sepoliaViem.getContractAt("PrivateBudgetGuard", deployed.address, {
          client: { public: ctx.sepolia.publicClient, wallet: walletB },
        })
      : undefined;
    const budgetGuardCoti = await cotiViem.deployContract(
      remoteContractName,
      [ctx.contracts.inboxCoti.address],
      {
        client: {
          public: ctx.coti.publicClient,
          wallet: ctx.coti.wallet,
        },
      } as any
    );
    await budgetGuard.write.configure(podConfigureKeepInbox(budgetGuardCoti.address, ctx.chainIds.coti));
    return { budgetGuard, budgetGuardAsB, budgetGuardCoti };
  };

  before(async function () {
    process.env.COTI_REUSE_CONTRACTS = "false";
    ctx = await setupContext({ sepoliaViem, cotiViem });

    const primaryKey = requirePrivateKey("COTI_TESTNET_PRIVATE_KEY");
    const normalizedPrimaryKey = normalizePrivateKey(primaryKey).toLowerCase();
    const inputSignerPrivateKey = EXPLICIT_COTI_SYSTEM_KEY || primaryKey;
    const inputSignerLabel = EXPLICIT_COTI_SYSTEM_KEY ? "dedicated COTI system signer" : "user A signer fallback";

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
      normalizePrivateKey(primaryKey) as `0x${string}`
    );
    await ensureFunds(accountA.address);

    walletA = createWalletClient({
      account: accountA,
      chain: ctx.sepolia.publicClient.chain,
      transport,
    });

    if (normalizePrivateKey(inputSignerPrivateKey).toLowerCase() === normalizedPrimaryKey) {
      inputSignerCrypto = ctx.crypto;
    } else {
      inputSignerCrypto = await getCotiCrypto(
        inputSignerPrivateKey,
        process.env.COTI_TESTNET_RPC_URL || "",
        "COTI_SYSTEM_AES_KEY"
      );
    }
    logStep(`Using ${inputSignerLabel} ${inputSignerCrypto.cotiEncryptWallet.address} for MPC input encryption`);

    if (EXPLICIT_SECOND_COTI_KEY) {
      cryptoB = await getCotiCrypto(
        EXPLICIT_SECOND_COTI_KEY,
        process.env.COTI_TESTNET_RPC_URL || "",
        "USER_AES_KEY_2"
      );
      const accountB = privateKeyToAccount(normalizePrivateKey(EXPLICIT_SECOND_COTI_KEY) as `0x${string}`);
      await ensureFunds(accountB.address);
      walletB = createWalletClient({
        account: accountB,
        chain: ctx.sepolia.publicClient.chain,
        transport,
      });
    }
  });

  it("registers a budget and evaluates approved, rejected, and exact spends", async function () {
    const { budgetGuard } = await deployBudgetGuard();

    logStep("Registering budget for user A");
    const budgetA = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 100n);
    let txHash = await budgetGuard.write.registerBudget(
      [budgetA, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-register-a");
    assert.equal(await budgetGuard.read.budgetInitialized([walletA.account.address]), true);
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      100n
    );

    logStep("Submitting approved spend for user A");
    const spendAApproved = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 35n);
    txHash = await budgetGuard.write.submitSpend(
      [spendAApproved, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-spend-a-approved");
    assert.equal(
      decryptCtBool(await budgetGuard.read.lastApprovalOf([walletA.account.address]), ctx.crypto.userKey),
      true
    );
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      65n
    );

    logStep("Submitting rejected spend for user A");
    const spendARejected = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 80n);
    txHash = await budgetGuard.write.submitSpend(
      [spendARejected, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-spend-a-rejected");
    assert.equal(
      decryptCtBool(await budgetGuard.read.lastApprovalOf([walletA.account.address]), ctx.crypto.userKey),
      false
    );
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      65n
    );

    logStep("Submitting exact spend for user A");
    const spendAExact = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 65n);
    txHash = await budgetGuard.write.submitSpend(
      [spendAExact, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-spend-a-exact");
    assert.equal(
      decryptCtBool(await budgetGuard.read.lastApprovalOf([walletA.account.address]), ctx.crypto.userKey),
      true
    );
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      0n
    );
  });

  it("rejects spend attempts before a budget is registered", async function () {
    const { budgetGuard } = await deployBudgetGuard();
    const spend = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 5n);

    await expectReject(
      () =>
        budgetGuard.write.submitSpend(
          [spend, ctx.podTwoWayFees.callbackFeeWei],
          podTwoWayWriteOptions(ctx.podTwoWayFees)
        ),
      "BudgetNotReady"
    );
  });

  it("blocks new requests while registration is pending, then clears the pending flag", async function () {
    const { budgetGuard } = await deployBudgetGuard();
    const budget = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 100n);
    const spend = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 1n);

    const txHash = await budgetGuard.write.registerBudget(
      [budget, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });

    const pendingRegister = await budgetGuard.read.pendingRegisterRequestIdOf([walletA.account.address]);
    assert.notEqual(pendingRegister, ZERO_REQUEST_ID);

    await expectReject(
      () =>
        budgetGuard.write.registerBudget(
          [budget, ctx.podTwoWayFees.callbackFeeWei],
          podTwoWayWriteOptions(ctx.podTwoWayFees)
        ),
      "BudgetRegistrationPending"
    );
    await expectReject(
      () =>
        budgetGuard.write.submitSpend(
          [spend, ctx.podTwoWayFees.callbackFeeWei],
          podTwoWayWriteOptions(ctx.podTwoWayFees)
        ),
      "BudgetRegistrationPending"
    );

    await runCrossChainTwoWayRoundTrip(ctx, "budget-pending-register");
    assert.equal(await budgetGuard.read.pendingRegisterRequestIdOf([walletA.account.address]), ZERO_REQUEST_ID);
  });

  it("lets the owner clear a stuck pending request so the user can continue", async function () {
    const { budgetGuard } = await deployBudgetGuard();
    const budget = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 100n);

    let txHash = await budgetGuard.write.registerBudget(
      [budget, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });

    const pendingRegister = await budgetGuard.read.pendingRegisterRequestIdOf([walletA.account.address]);
    assert.notEqual(pendingRegister, ZERO_REQUEST_ID);

    await budgetGuard.write.clearPending([walletA.account.address]);
    assert.equal(await budgetGuard.read.pendingRegisterRequestIdOf([walletA.account.address]), ZERO_REQUEST_ID);
    assert.equal(await budgetGuard.read.pendingSpendRequestIdOf([walletA.account.address]), ZERO_REQUEST_ID);

    // Drain the original cross-chain request so the shared inbox harness stays clean.
    await runCrossChainTwoWayRoundTrip(ctx, "budget-clear-pending-original");
    assert.equal(await budgetGuard.read.pendingRegisterRequestIdOf([walletA.account.address]), ZERO_REQUEST_ID);

    txHash = await budgetGuard.write.submitSpend(
      [await encryptFor(inputSignerCrypto.cotiEncryptWallet, 40n), ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-clear-pending-spend");
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      60n
    );
  });

  it("blocks concurrent spends and re-registration while a spend is pending, then clears the pending flag", async function () {
    const { budgetGuard } = await deployBudgetGuard();
    const budget = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 100n);
    let txHash = await budgetGuard.write.registerBudget(
      [budget, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-pending-spend-register");

    const spend = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 25n);
    txHash = await budgetGuard.write.submitSpend(
      [spend, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });

    const pendingSpend = await budgetGuard.read.pendingSpendRequestIdOf([walletA.account.address]);
    assert.notEqual(pendingSpend, ZERO_REQUEST_ID);

    await expectReject(
      () =>
        budgetGuard.write.submitSpend(
          [spend, ctx.podTwoWayFees.callbackFeeWei],
          podTwoWayWriteOptions(ctx.podTwoWayFees)
        ),
      "SpendAlreadyPending"
    );
    await expectReject(
      () =>
        budgetGuard.write.registerBudget(
          [budget, ctx.podTwoWayFees.callbackFeeWei],
          podTwoWayWriteOptions(ctx.podTwoWayFees)
        ),
      "SpendAlreadyPending"
    );

    await runCrossChainTwoWayRoundTrip(ctx, "budget-pending-spend");
    assert.equal(await budgetGuard.read.pendingSpendRequestIdOf([walletA.account.address]), ZERO_REQUEST_ID);
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      75n
    );
  });

  it("allows re-registering a budget and overwrites the previous remaining amount", async function () {
    const { budgetGuard } = await deployBudgetGuard();

    let txHash = await budgetGuard.write.registerBudget(
      [await encryptFor(inputSignerCrypto.cotiEncryptWallet, 100n), ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-reregister-initial");
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      100n
    );

    txHash = await budgetGuard.write.registerBudget(
      [await encryptFor(inputSignerCrypto.cotiEncryptWallet, 250n), ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-reregister-overwrite");
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      250n
    );
  });

  it("clears pending spend state after a forced remote error and can recover afterwards", async function () {
    const { budgetGuard, budgetGuardCoti } = await deployBudgetGuard();

    let txHash = await budgetGuard.write.registerBudget(
      [await encryptFor(inputSignerCrypto.cotiEncryptWallet, 100n), ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-error-register");
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      100n
    );

    const failingBudgetGuardCoti = await cotiViem.deployContract(
      "PrivateBudgetGuardCotiFailureHarness",
      [ctx.contracts.inboxCoti.address],
      {
        client: {
          public: ctx.coti.publicClient,
          wallet: ctx.coti.wallet,
        },
      } as any
    );
    await budgetGuard.write.configure(podConfigureKeepInbox(failingBudgetGuardCoti.address, ctx.chainIds.coti));

    txHash = await budgetGuard.write.submitSpend(
      [await encryptFor(inputSignerCrypto.cotiEncryptWallet, 30n), ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    const pendingBeforeError = await budgetGuard.read.pendingSpendRequestIdOf([walletA.account.address]);
    assert.notEqual(pendingBeforeError, ZERO_REQUEST_ID);

    await runCrossChainTwoWayRoundTrip(ctx, "budget-error-spend");
    assert.equal(await budgetGuard.read.pendingSpendRequestIdOf([walletA.account.address]), ZERO_REQUEST_ID);
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      100n
    );

    await budgetGuard.write.configure(podConfigureKeepInbox(budgetGuardCoti.address, ctx.chainIds.coti));
    txHash = await budgetGuard.write.submitSpend(
      [await encryptFor(inputSignerCrypto.cotiEncryptWallet, 30n), ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-error-recovery");
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      70n
    );
    assert.equal(
      decryptCtBool(await budgetGuard.read.lastApprovalOf([walletA.account.address]), ctx.crypto.userKey),
      true
    );
  });

  (EXPLICIT_SECOND_COTI_KEY ? it : it.skip)("isolates budgets across two users with a shared COTI-side input signer", async function () {
    assert.ok(cryptoB, "Expected second COTI user crypto");
    assert.ok(walletB, "Expected second wallet client");

    const { budgetGuard, budgetGuardAsB } = await deployBudgetGuard();
    assert.ok(budgetGuardAsB, "Expected second contract client");

    logStep("Registering budget for user A");
    const budgetA = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 100n);
    let txHash = await budgetGuard.write.registerBudget(
      [budgetA, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-multi-register-a");

    logStep("Registering budget for user B");
    // Wallet B is the source-chain caller and `USER_AES_KEY_2` decrypts B's outputs,
    // but MPC inputs are still authored by the shared COTI-side signer configured above.
    const budgetB = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 200n);
    txHash = await budgetGuardAsB.write.registerBudget(
      [budgetB, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-multi-register-b");

    assert.equal(await budgetGuard.read.budgetInitialized([walletA.account.address]), true);
    assert.equal(await budgetGuard.read.budgetInitialized([walletB.account.address]), true);
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      100n
    );
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletB.account.address]), cryptoB.userKey),
      200n
    );

    logStep("Submitting approved spend for user B");
    const spendBApproved = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 50n);
    txHash = await budgetGuardAsB.write.submitSpend(
      [spendBApproved, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-multi-spend-b-approved");

    assert.equal(
      decryptCtBool(await budgetGuard.read.lastApprovalOf([walletB.account.address]), cryptoB.userKey),
      true
    );
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletB.account.address]), cryptoB.userKey),
      150n
    );
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      100n
    );

    logStep("Submitting approved spend for user A");
    const spendAApproved = await encryptFor(inputSignerCrypto.cotiEncryptWallet, 40n);
    txHash = await budgetGuard.write.submitSpend(
      [spendAApproved, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    await runCrossChainTwoWayRoundTrip(ctx, "budget-multi-spend-a-approved");

    assert.equal(
      decryptCtBool(await budgetGuard.read.lastApprovalOf([walletA.account.address]), ctx.crypto.userKey),
      true
    );
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletA.account.address]), ctx.crypto.userKey),
      60n
    );
    assert.equal(
      decryptCtUint64(await budgetGuard.read.remainingBudgetOf([walletB.account.address]), cryptoB.userKey),
      150n
    );
  });
});
