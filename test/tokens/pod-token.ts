/**
 * Cross-chain `PodERC20` + `PodErc20CotiSide` tests (mint/sync, transfer, approve, pending, errors).
 *
 * These exercises COTI MPC on garbled 256-bit balances (`syncBalances` uses `offBoardToUser` per account). If
 * `batchProcessRequests` fails, try raising `COTI_MINE_GAS_POD_TOKEN`.
 *
 * Run explicitly: `npm run test:pod-token` (sets `POD_TOKEN_SYSTEM_TESTS=1`).
 * Running `hardhat test test/tokens/pod-token.ts` without that env skips the whole suite (`-` in node:test output);
 * skipped suites do not run `before` or `it`, so there are no step logs unless you enable the flag.
 *
 * Step logs use `[mpc-test] pod-token: …` (see `pt()`); grep `pod-token` in the test output to follow phases.
 */
import assert from "node:assert/strict";
import { before, describe, it } from "node:test";
import { network } from "hardhat";
import { logStep } from "../system/mpc-test-utils.js";
import {
  assertIncludesInsensitive,
  completePodOpRoundTrip,
  encryptAmount,
  mineLatestOutboundRoundTrip,
  mintOnCoti,
  mintOnCotiAndSync,
  syncPodBalancesRoundTrip,
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

if (!runPodTokenSystem) {
  logStep(
    "pod-token: suite skipped — POD_TOKEN_SYSTEM_TESTS is not \"1\", so `before`/tests never run and no step logs appear. Use: npm run test:pod-token"
  );
}

/** Step log for this suite (grep `pod-token`). */
const pt = (message: string) => logStep(`pod-token: ${message}`);

d("PodERC20 (cross-chain token)", async function () {
  const { viem: sepoliaViem } = await network.connect({ network: "hardhat" });
  const { viem: cotiViem } = await network.connect({ network: "cotiTestnet" });

  let ctx: PodTokenTestContext;

  before(async function () {
    pt("before: connecting networks and deploying PodERC20 + PodErc20CotiSide");
    // Fresh COTI inbox + token pairing avoids stale `raise`/nonce state vs newly deployed `PodErc20CotiSide`.
    if (process.env.COTI_REUSE_CONTRACTS === undefined) {
      process.env.COTI_REUSE_CONTRACTS = "false";
    }
    ctx = await setupPodTokenTestContext({ sepoliaViem, cotiViem });
    pt("before: seed Bob on COTI + sync so PoD balanceOf(Bob) is valid zero ciphertext (not uninitialized storage)");
    await mintOnCoti(ctx, ctx.bob.address, 0n);
    await syncPodBalancesRoundTrip(ctx, [ctx.bob.address], "seedBobZero");
    pt(`before: ready (owner=${ctx.owner}, bob=${ctx.bob.address}, pod=${ctx.pod.address})`);
  });

  it("mint on COTI + sync on PoD updates balances", async function () {
    pt("case mint+sync: start");
    const amount = 10_000n;
    pt(`case mint+sync: mintOnCotiAndSync owner amount=${amount}`);
    await mintOnCotiAndSync(ctx, [{ address: ctx.owner, amount }], "mintSyncOwner");

    pt("case mint+sync: read decrypted balance + pending flag");
    const bal = await readDecryptedBalance(ctx, ctx.owner);
    assert.equal(bal, amount);
    const st = await readBalanceWithPending(ctx, ctx.owner);
    assert.equal(st.pending, false);
    pt("case mint+sync: done (balance matches, not pending)");
  });

  it("simple transfer: round-trip updates sender and receiver balances", async function () {
    pt("case simple transfer: start");
    const start = 5_000n;
    const sendAmt = 1_200n;
    const ownerBefore = await readDecryptedBalance(ctx, ctx.owner);
    const bobBefore = await readDecryptedBalance(ctx, ctx.bob.address);
    pt(`case simple transfer: fund owner with ${start}`);
    await mintOnCotiAndSync(ctx, [{ address: ctx.owner, amount: start }], "xferFund");
    assert.equal(await readDecryptedBalance(ctx, ctx.owner), ownerBefore + start);

    pt(`case simple transfer: encrypt ${sendAmt} and run transfer round-trip`);
    const itAmount = await encryptAmount(ctx, sendAmt);
    await completePodOpRoundTrip(ctx, "xferSimple", () =>
      ctx.podAsCoti.write.transfer([ctx.bob.address, itAmount])
    );

    pt("case simple transfer: assert owner and bob balances");
    assert.equal(await readDecryptedBalance(ctx, ctx.owner), ownerBefore + start - sendAmt);
    assert.equal(await readDecryptedBalance(ctx, ctx.bob.address), bobBefore + sendAmt);
    pt("case simple transfer: done");
  });

  it("approve then transferFrom updates balances and allowance", async function () {
    pt("case approve+transferFrom: start");
    const start = 8_000n;
    const allowanceAmt = 3_000n;
    const spendAmt = 2_000n;
    const ownerBefore = await readDecryptedBalance(ctx, ctx.owner);
    const bobBefore = await readDecryptedBalance(ctx, ctx.bob.address);
    pt(`case approve+transferFrom: fund owner ${start}`);
    await mintOnCotiAndSync(ctx, [{ address: ctx.owner, amount: start }], "apprFund");
    assert.equal(await readDecryptedBalance(ctx, ctx.owner), ownerBefore + start);

    const itAllow = await encryptAmount(ctx, allowanceAmt);
    let ap = await readAllowanceWithPending(ctx, ctx.owner, ctx.owner);
    assert.equal(ap.pending, false);
    pt(`case approve+transferFrom: approve self allowance=${allowanceAmt}`);
    await completePodOpRoundTrip(ctx, "apprSelf", () =>
      ctx.podAsCoti.write.approve([ctx.owner, itAllow])
    );

    ap = await readAllowanceWithPending(ctx, ctx.owner, ctx.owner);
    assert.equal(ap.pending, false);
    const dec = await readDecryptedAllowance(ctx, ctx.owner, ctx.owner);
    assert.equal(dec.ownerCt, allowanceAmt);
    assert.equal(dec.spenderCt, allowanceAmt);
    pt("case approve+transferFrom: allowance ciphertexts match");

    pt(`case approve+transferFrom: transferFrom owner→bob spend=${spendAmt}`);
    const itSpend = await encryptAmount(ctx, spendAmt);
    await completePodOpRoundTrip(ctx, "xferFrom", () =>
      ctx.podAsCoti.write.transferFrom([ctx.owner, ctx.bob.address, itSpend])
    );

    assert.equal(await readDecryptedBalance(ctx, ctx.owner), ownerBefore + start - spendAmt);
    assert.equal(await readDecryptedBalance(ctx, ctx.bob.address), bobBefore + spendAmt);
    // Allowance is not reduced on the PoD mirror today (`PodErc20CotiSide.transferFrom` does not touch garbled allowance);
    // balances above confirm approve + transferFrom round-trips succeeded.
    const after = await readDecryptedAllowance(ctx, ctx.owner, ctx.owner);
    assert.equal(after.ownerCt, allowanceAmt);
    assert.equal(after.spenderCt, allowanceAmt);
    pt("case approve+transferFrom: done (PoD allowance mirror unchanged as expected)");
  });

  it("reverts with TransferAlreadyPending while a transfer is in flight", async function () {
    pt("case pending guard: start");
    const start = 4_000n;
    const ownerBefore = await readDecryptedBalance(ctx, ctx.owner);
    pt(`case pending guard: fund owner ${start}`);
    await mintOnCotiAndSync(ctx, [{ address: ctx.owner, amount: start }], "pendFund");
    assert.equal(await readDecryptedBalance(ctx, ctx.owner), ownerBefore + start);

    pt("case pending guard: submit first transfer (PoD only, not mined yet on COTI)");
    const itSmall = await encryptAmount(ctx, 100n);
    const txHash = await ctx.podAsCoti.write.transfer([ctx.bob.address, itSmall]);
    await ctx.base.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash });

    const mid = await readBalanceWithPending(ctx, ctx.owner);
    assert.equal(mid.pending, true);
    pt("case pending guard: owner pending=true, expect second transfer to revert");

    const itAnother = await encryptAmount(ctx, 200n);
    await assert.rejects(
      () => ctx.podAsCoti.write.transfer([ctx.bob.address, itAnother]),
      (e: unknown) => {
        const msg = e instanceof Error ? e.message : String(e);
        return msg.includes("TransferAlreadyPending");
      }
    );

    pt("case pending guard: mine round-trip to clear pending");
    await mineLatestOutboundRoundTrip(ctx, "pendClear");
    const end = await readBalanceWithPending(ctx, ctx.owner);
    assert.equal(end.pending, false);
    assert.equal(end.balance, ownerBefore + start - 100n);
    pt("case pending guard: done (cleared, balance reduced by 100)");
  });

  it("failed transfer clears pending and stores a meaningful error", async function () {
    pt("case failed transfer: start");
    const start = 500n;
    const ownerBefore = await readDecryptedBalance(ctx, ctx.owner);
    const bobBefore = await readDecryptedBalance(ctx, ctx.bob.address);
    pt(`case failed transfer: fund owner ${start}, then attempt transfer > balance`);
    await mintOnCotiAndSync(ctx, [{ address: ctx.owner, amount: start }], "failFund");
    const ownerAfterMint = await readDecryptedBalance(ctx, ctx.owner);
    assert.equal(ownerAfterMint, ownerBefore + start);

    const tooMuch = ownerAfterMint + 1n;
    pt(`case failed transfer: attempt ${tooMuch} (> balance ${ownerAfterMint})`);
    const itAmount = await encryptAmount(ctx, tooMuch);
    pt("case failed transfer: round-trip (COTI should reject insufficient balance)");
    const { cotiIncomingRequestId } = await completePodOpRoundTrip(ctx, "failXfer", () =>
      ctx.podAsCoti.write.transfer([ctx.bob.address, itAmount])
    );

    const st = await readBalanceWithPending(ctx, ctx.owner);
    assert.equal(st.pending, false);
    const ownerAfterFail = await readDecryptedBalance(ctx, ctx.owner);
    assert.equal(ownerAfterFail, ownerAfterMint);
    assert.equal(await readDecryptedBalance(ctx, ctx.bob.address), bobBefore);
    pt(`case failed transfer: pending cleared, failedRequests key=${cotiIncomingRequestId}`);

    const errHex = (await ctx.pod.read.failedRequests([cotiIncomingRequestId])) as `0x${string}`;
    const text = utf8FromFailedRequestBytes(errHex);
    assertIncludesInsensitive(text, "insufficient");
    pt(`case failed transfer: done (error text includes "insufficient")`);
  });
});
