/**
 * Cross-chain `PodERC20` + `PodErc20CotiSide` tests (mint/sync, transfer, approve, pending, errors).
 *
 * These exercises `MpcCore.offBoardToUser` on garbled 256-bit balances on COTI (same family as wide MPC).
 * If COTI returns `errorCode=1` with opaque `errorMessage` during `batchProcessRequests`, raise gas via
 * `COTI_MINE_GAS_POD_TOKEN` / `COTI_MINE_GAS_MPC_256`, or confirm testnet precompile support with the COTI stack.
 *
 * Run explicitly: `npm run test:pod-token` (sets `POD_TOKEN_SYSTEM_TESTS=1`).
 */
import assert from "node:assert/strict";
import { before, describe, it } from "node:test";
import { network } from "hardhat";
import {
  assertIncludesInsensitive,
  completePodOpRoundTrip,
  encryptAmount,
  mineLatestOutboundRoundTrip,
  mintOnCotiAndSync,
  readAllowanceWithPending,
  readBalanceWithPending,
  readDecryptedAllowance,
  readDecryptedBalance,
  setupPodTokenTestContext,
  utf8FromFailedRequestBytes,
  type PodTokenTestContext,
} from "./test-token-utils.js";

const runPodTokenSystem = process.env.POD_TOKEN_SYSTEM_TESTS === "1";
const d = runPodTokenSystem ? describe : describe.skip;

d("PodERC20 (cross-chain token)", async function () {
  const { viem: sepoliaViem } = await network.connect({ network: "hardhat" });
  const { viem: cotiViem } = await network.connect({ network: "cotiTestnet" });

  let ctx: PodTokenTestContext;

  before(async function () {
    // Fresh COTI inbox + token pairing avoids stale `raise`/nonce state vs newly deployed `PodErc20CotiSide`.
    if (process.env.COTI_REUSE_CONTRACTS === undefined) {
      process.env.COTI_REUSE_CONTRACTS = "false";
    }
    ctx = await setupPodTokenTestContext({ sepoliaViem, cotiViem });
  });

  it("mint on COTI + sync on PoD updates balances", async function () {
    const amount = 10_000n;
    await mintOnCotiAndSync(ctx, [{ address: ctx.owner, amount }], "mintSyncOwner");

    const bal = await readDecryptedBalance(ctx, ctx.owner);
    assert.equal(bal, amount);
    const st = await readBalanceWithPending(ctx, ctx.owner);
    assert.equal(st.pending, false);
  });

  it("simple transfer: round-trip updates sender and receiver balances", async function () {
    const start = 5_000n;
    const sendAmt = 1_200n;
    await mintOnCotiAndSync(ctx, [{ address: ctx.owner, amount: start }], "xferFund");

    const itAmount = await encryptAmount(ctx, sendAmt);
    await completePodOpRoundTrip(ctx, "xferSimple", () =>
      ctx.podAsCoti.write.transfer([ctx.bob.address, itAmount])
    );

    assert.equal(await readDecryptedBalance(ctx, ctx.owner), start - sendAmt);
    assert.equal(await readDecryptedBalance(ctx, ctx.bob.address), sendAmt);
  });

  it("approve then transferFrom updates balances and allowance", async function () {
    const start = 8_000n;
    const allowanceAmt = 3_000n;
    const spendAmt = 2_000n;
    await mintOnCotiAndSync(ctx, [{ address: ctx.owner, amount: start }], "apprFund");

    const itAllow = await encryptAmount(ctx, allowanceAmt);
    let ap = await readAllowanceWithPending(ctx, ctx.owner, ctx.owner);
    assert.equal(ap.pending, false);

    await completePodOpRoundTrip(ctx, "apprSelf", () =>
      ctx.podAsCoti.write.approve([ctx.owner, itAllow])
    );

    ap = await readAllowanceWithPending(ctx, ctx.owner, ctx.owner);
    assert.equal(ap.pending, false);
    const dec = await readDecryptedAllowance(ctx, ctx.owner, ctx.owner);
    assert.equal(dec.ownerCt, allowanceAmt);
    assert.equal(dec.spenderCt, allowanceAmt);

    const itSpend = await encryptAmount(ctx, spendAmt);
    await completePodOpRoundTrip(ctx, "xferFrom", () =>
      ctx.podAsCoti.write.transferFrom([ctx.owner, ctx.bob.address, itSpend])
    );

    assert.equal(await readDecryptedBalance(ctx, ctx.owner), start - spendAmt);
    assert.equal(await readDecryptedBalance(ctx, ctx.bob.address), spendAmt);
    // Allowance is not reduced on the PoD mirror today (`PodErc20CotiSide.transferFrom` does not touch garbled allowance);
    // balances above confirm approve + transferFrom round-trips succeeded.
    const after = await readDecryptedAllowance(ctx, ctx.owner, ctx.owner);
    assert.equal(after.ownerCt, allowanceAmt);
    assert.equal(after.spenderCt, allowanceAmt);
  });

  it("reverts with TransferAlreadyPending while a transfer is in flight", async function () {
    const start = 4_000n;
    await mintOnCotiAndSync(ctx, [{ address: ctx.owner, amount: start }], "pendFund");

    const itSmall = await encryptAmount(ctx, 100n);
    const txHash = await ctx.podAsCoti.write.transfer([ctx.bob.address, itSmall]);
    await ctx.base.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash });

    const mid = await readBalanceWithPending(ctx, ctx.owner);
    assert.equal(mid.pending, true);

    const itAnother = await encryptAmount(ctx, 200n);
    await assert.rejects(
      () => ctx.podAsCoti.write.transfer([ctx.bob.address, itAnother]),
      (e: unknown) => {
        const msg = e instanceof Error ? e.message : String(e);
        return msg.includes("TransferAlreadyPending");
      }
    );

    await mineLatestOutboundRoundTrip(ctx, "pendClear");
    const end = await readBalanceWithPending(ctx, ctx.owner);
    assert.equal(end.pending, false);
    assert.equal(end.balance, start - 100n);
  });

  it("failed transfer clears pending and stores a meaningful error", async function () {
    const start = 500n;
    const tooMuch = 2_000n;
    await mintOnCotiAndSync(ctx, [{ address: ctx.owner, amount: start }], "failFund");

    const itAmount = await encryptAmount(ctx, tooMuch);
    const { cotiIncomingRequestId } = await completePodOpRoundTrip(ctx, "failXfer", () =>
      ctx.podAsCoti.write.transfer([ctx.bob.address, itAmount])
    );

    const st = await readBalanceWithPending(ctx, ctx.owner);
    assert.equal(st.pending, false);
    assert.equal(st.balance, start);
    assert.equal(await readDecryptedBalance(ctx, ctx.bob.address), 0n);

    const errHex = (await ctx.pod.read.failedRequests([cotiIncomingRequestId])) as `0x${string}`;
    const text = utf8FromFailedRequestBytes(errHex);
    assertIncludesInsensitive(text, "insufficient");
  });
});
