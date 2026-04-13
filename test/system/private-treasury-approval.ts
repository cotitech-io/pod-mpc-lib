import assert from "node:assert/strict";
import { afterEach, before, describe, it } from "node:test";
import { network } from "hardhat";
import { decryptUint } from "@coti-io/coti-sdk-typescript";
import { privateKeyToAccount } from "viem/accounts";
import { createWalletClient, custom, parseEther, zeroAddress } from "viem";
import {
  buildEncryptedBool,
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

const EXPLICIT_COTI_SYSTEM_KEY = process.env.COTI_SYSTEM_PRIVATE_KEY?.trim() || "";
const ZERO_REQUEST_ID = `0x${"0".repeat(64)}` as const;
const DESCRIPTION_HASH = `0x${"11".repeat(32)}` as const;
const PAYOUT_RECIPIENT = "0x00000000000000000000000000000000000000A1" as const;

describe("PrivateTreasuryApproval (system)", async function () {
  const { viem: sepoliaViem } = await network.connect({ network: "hardhat" });
  const { viem: cotiViem } = await network.connect({ network: "cotiTestnet" });

  let ctx: TestContext;
  let walletA: any;
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
  const getProposalFlag = async (treasury: any, proposalId: bigint, field: string, index: number) =>
    getTupleField(await treasury.read.proposals([proposalId]), field, index);
  const increaseSourceTime = async (seconds: number) => {
    await ctx.sepolia.publicClient.request({
      method: "evm_increaseTime",
      params: [seconds],
    });
    await ctx.sepolia.publicClient.request({
      method: "evm_mine",
      params: [],
    });
  };

  const deployTreasuryApproval = async (
    remoteContractName:
      | "PrivateTreasuryApprovalCoti"
      | "PrivateTreasuryApprovalCotiFailureHarness" = "PrivateTreasuryApprovalCoti"
  ) => {
    const deployed = await sepoliaViem.deployContract("PrivateTreasuryApproval", [ctx.contracts.inboxSepolia.address], {
      client: { public: ctx.sepolia.publicClient, wallet: walletA },
    });
    const treasury = await sepoliaViem.getContractAt("PrivateTreasuryApproval", deployed.address, {
      client: { public: ctx.sepolia.publicClient, wallet: walletA },
    });
    const treasuryCoti = await cotiViem.deployContract(
      remoteContractName,
      [ctx.contracts.inboxCoti.address],
      {
        client: {
          public: ctx.coti.publicClient,
          wallet: ctx.coti.wallet,
        },
      } as any
    );
    await treasury.write.configure(podConfigureKeepInbox(treasuryCoti.address, ctx.chainIds.coti));
    return { treasury, treasuryCoti };
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
  });

  it("registers a payout proposal, records a private approval, finalizes, and executes an ETH payout", async function () {
    const { treasury } = await deployTreasuryApproval();
    const fundTx = await walletA.sendTransaction({ to: treasury.address, value: parseEther("1") });
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: fundTx, ...receiptWaitOptions });

    const proposalId = await treasury.read.nextProposalId();
    const now = (await ctx.sepolia.publicClient.getBlock()).timestamp;
    const payoutAmount = parseEther("0.2");

    logStep("Creating treasury payout proposal");
    let txHash = await treasury.write.createProposal(
      [
        PAYOUT_RECIPIENT,
        zeroAddress,
        payoutAmount,
        DESCRIPTION_HASH,
        now + 120n,
        1n,
        [walletA.account.address],
        ctx.podTwoWayFees.callbackFeeWei,
      ],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    assert.notEqual(await treasury.read.pendingRegisterRequestIdOf([proposalId]), ZERO_REQUEST_ID);

    await runCrossChainTwoWayRoundTrip(ctx, "treasury-register");
    assert.equal(await getProposalFlag(treasury, proposalId, "registered", 7), true);
    assert.equal(await treasury.read.pendingRegisterRequestIdOf([proposalId]), ZERO_REQUEST_ID);

    logStep("Casting private approval");
    const support = await buildEncryptedBool(
      {
        crypto: { userKey: "", cotiEncryptWallet: inputSignerCrypto.cotiEncryptWallet },
        contracts: { inboxCoti: { address: ctx.contracts.inboxCoti.address as `0x${string}` } },
      },
      1
    );
    txHash = await treasury.write.castApproval(
      [proposalId, support, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    assert.notEqual(
      await treasury.read.pendingApprovalRequestIdOf([proposalId, walletA.account.address]),
      ZERO_REQUEST_ID
    );
    assert.equal(await treasury.read.pendingApprovalCountOf([proposalId]), 1n);

    await runCrossChainTwoWayRoundTrip(ctx, "treasury-approval");
    assert.equal(
      await treasury.read.pendingApprovalRequestIdOf([proposalId, walletA.account.address]),
      ZERO_REQUEST_ID
    );
    assert.equal(await treasury.read.pendingApprovalCountOf([proposalId]), 0n);
    assert.equal(
      decryptCtBool(await treasury.read.recordedVoteReceiptOf([proposalId, walletA.account.address]), ctx.crypto.userKey),
      true
    );

    await increaseSourceTime(121);

    logStep("Finalizing approved proposal");
    txHash = await treasury.write.finalizeProposal(
      [proposalId, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    assert.notEqual(await treasury.read.pendingFinalizeRequestIdOf([proposalId]), ZERO_REQUEST_ID);

    await runCrossChainTwoWayRoundTrip(ctx, "treasury-finalize");
    assert.equal(await treasury.read.pendingFinalizeRequestIdOf([proposalId]), ZERO_REQUEST_ID);
    assert.equal(await getProposalFlag(treasury, proposalId, "finalized", 8), true);
    assert.equal(await getProposalFlag(treasury, proposalId, "approved", 9), true);
    assert.equal(decryptCtUint64(await treasury.read.encryptedYesVotesOf([proposalId]), ctx.crypto.userKey), 1n);
    assert.equal(decryptCtUint64(await treasury.read.encryptedNoVotesOf([proposalId]), ctx.crypto.userKey), 0n);

    const balanceBefore = await ctx.sepolia.publicClient.getBalance({ address: PAYOUT_RECIPIENT });
    txHash = await treasury.write.executeProposal([proposalId]);
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    const balanceAfter = await ctx.sepolia.publicClient.getBalance({ address: PAYOUT_RECIPIENT });
    assert.equal(balanceAfter - balanceBefore, payoutAmount);
    assert.equal(await getProposalFlag(treasury, proposalId, "executed", 10), true);
  });

  it("recovers from a failed remote registration by retrying against the real COTI contract", async function () {
    const { treasury, treasuryCoti } = await deployTreasuryApproval("PrivateTreasuryApprovalCotiFailureHarness");
    const proposalId = await treasury.read.nextProposalId();
    const now = (await ctx.sepolia.publicClient.getBlock()).timestamp;

    let txHash = await treasury.write.createProposal(
      [
        PAYOUT_RECIPIENT,
        zeroAddress,
        parseEther("0.05"),
        DESCRIPTION_HASH,
        now + 120n,
        1n,
        [walletA.account.address],
        ctx.podTwoWayFees.callbackFeeWei,
      ],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });

    await runCrossChainTwoWayRoundTrip(ctx, "treasury-register-fail");
    assert.equal(await treasury.read.pendingRegisterRequestIdOf([proposalId]), ZERO_REQUEST_ID);
    assert.equal(await getProposalFlag(treasury, proposalId, "registered", 7), false);

    const realCoti = await cotiViem.deployContract("PrivateTreasuryApprovalCoti", [ctx.contracts.inboxCoti.address], {
      client: {
        public: ctx.coti.publicClient,
        wallet: ctx.coti.wallet,
      },
    } as any);
    await treasury.write.configure(podConfigureKeepInbox(realCoti.address, ctx.chainIds.coti));

    txHash = await treasury.write.registerProposalRemote(
      [proposalId, ctx.podTwoWayFees.callbackFeeWei],
      podTwoWayWriteOptions(ctx.podTwoWayFees)
    );
    await ctx.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
    assert.notEqual(await treasury.read.pendingRegisterRequestIdOf([proposalId]), ZERO_REQUEST_ID);

    await runCrossChainTwoWayRoundTrip(ctx, "treasury-register-retry");
    assert.equal(await treasury.read.pendingRegisterRequestIdOf([proposalId]), ZERO_REQUEST_ID);
    assert.equal(await getProposalFlag(treasury, proposalId, "registered", 7), true);
    assert.ok(treasuryCoti.address, "Expected initial failing COTI contract");
  });
});
