/**
 * System pod op tests. Optional filters for faster iteration:
 * - `POD_OPS_SUITE` — substring of suite name to run (e.g. `PodTest256`). Other `describe` blocks are skipped.
 * - `POD_OPS_ONLY` — substring of row `label` (e.g. `mul256`, `add64`). Unmatched rows are skipped; trailing `rand64` / `rand128` / `rand256` checks honor the same filter when set.
 *
 * Examples:
 *   POD_OPS_SUITE=PodTest256 POD_OPS_ONLY=mul256 nht ./test/system/mpc-pod-ops.ts
 *   POD_OPS_ONLY=add64 nht ./test/system/mpc-pod-ops.ts
 *
 * If COTI reports `errorCode=1` / empty `errorMessage` on 256-bit ops (often OOG inside `MpcExecutor`), raise
 * `COTI_MINE_GAS_MPC_256` (default 50M in mpc-test-utils). For Hardhat `gas required exceeds allowance`, see
 * `POD_OPS_HARDHAT_GAS` (see `DEFAULT_POD_HARDHAT_GAS_256` in mpc-test-utils).
 */
import assert from "node:assert/strict";
import { before, describe, it } from "node:test";
import { network } from "hardhat";
import { decryptUint } from "@coti-io/coti-sdk-typescript";
import {
  buildEncryptedBool,
  buildEncryptedInput,
  buildEncryptedInput128,
  buildEncryptedInput256,
  decodePodCtUint64Word,
  decodePodCtUint128Struct,
  decodePodCtUint256Struct,
  decodePodPlainUint256,
  decryptUint128,
  decryptUint256,
  logStep,
  runPodRoundTrip,
  setupPodTestContext,
  type PodTestContext,
} from "./mpc-test-utils.js";

/**
 * First `setupPodTestContext` run redeploys COTI `MpcExecutor` once (inbox reused) so cached bytecode
 * matches `IPodExecutor*` (e.g. `add64`). Set `COTI_POD_OPS_SKIP_EXECUTOR_REFRESH=true` to skip when the
 * cached executor is already up to date.
 */
let podOpsCotiExecutorRefreshed = false;
function takePodOpsCotiExecutorRefresh(): boolean {
  if (process.env.COTI_POD_OPS_SKIP_EXECUTOR_REFRESH === "true") return false;
  if (podOpsCotiExecutorRefreshed) return false;
  podOpsCotiExecutorRefreshed = true;
  return true;
}

const POD_OPS_SUITE = process.env.POD_OPS_SUITE?.trim().toLowerCase() ?? "";
const POD_OPS_ONLY = process.env.POD_OPS_ONLY?.trim().toLowerCase() ?? "";

function podOpsSuiteEnabled(suiteName: string): boolean {
  if (!POD_OPS_SUITE) return true;
  return suiteName.toLowerCase().includes(POD_OPS_SUITE);
}

function podOpsRowEnabled(label: string): boolean {
  if (!POD_OPS_ONLY) return true;
  return label.toLowerCase().includes(POD_OPS_ONLY);
}

function filterPodOpsRows<T extends { label: string }>(rows: T[]): T[] {
  if (!POD_OPS_ONLY) return rows;
  return rows.filter((r) => podOpsRowEnabled(r.label));
}

function decryptU64Payload(raw: `0x${string}`, userKey: string): bigint {
  return decryptUint(decodePodCtUint64Word(raw), userKey);
}

function decryptU128Payload(raw: `0x${string}`, userKey: string): bigint {
  const st = decodePodCtUint128Struct(raw);
  return decryptUint128({ high: st.high, low: st.low }, userKey, decryptUint);
}

function decryptU256Payload(raw: `0x${string}`, userKey: string): bigint {
  const st = decodePodCtUint256Struct(raw);
  return decryptUint256(st, userKey, decryptUint);
}

describe("Pod MPC operations (system)", async function () {
  const { viem: sepoliaViem } = await network.connect({ network: "hardhat" });
  const { viem: cotiViem } = await network.connect({ network: "cotiTestnet" });

  const d64 = podOpsSuiteEnabled("PodTest64") ? describe : describe.skip;
  d64("PodTest64", function () {
    let ctx: PodTestContext;

    before(async function () {
      process.env.COTI_REUSE_CONTRACTS = "true";
      ctx = await setupPodTestContext({
        sepoliaViem,
        cotiViem,
        podContractName: "PodTest64",
        forceRedeployCotiExecutor: takePodOpsCotiExecutorRefresh(),
      });
    });

    it("runs table of 64-bit ops and checks decrypted results", async function () {
      const a = 15n;
      const b = 27n;
      const itA = await buildEncryptedInput(ctx, a);
      const itB = await buildEncryptedInput(ctx, b);
      const itEq = await buildEncryptedInput(ctx, 42n);
      const itOne = await buildEncryptedBool(ctx, 1);
      const itZero = await buildEncryptedBool(ctx, 0);

      type Row = {
        label: string;
        send: () => Promise<`0x${string}`>;
        check: (raw: `0x${string}`) => void;
      };

      const rows: Row[] = [
        {
          label: "add64",
          send: () => runPodRoundTrip(ctx, "add64", (c) => c.write.execAdd64([itA, itB])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), a + b),
        },
        {
          label: "sub64",
          send: () => runPodRoundTrip(ctx, "sub64", (c) => c.write.execSub64([itB, itA])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), b - a),
        },
        {
          label: "mul64",
          send: () => runPodRoundTrip(ctx, "mul64", (c) => c.write.execMul64([itA, itB])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), a * b),
        },
        {
          label: "div64",
          send: () => runPodRoundTrip(ctx, "div64", (c) => c.write.execDiv64([itB, itA])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), b / a),
        },
        {
          label: "rem64",
          send: () => runPodRoundTrip(ctx, "rem64", (c) => c.write.execRem64([itB, itA])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), b % a),
        },
        {
          label: "and64",
          send: () => runPodRoundTrip(ctx, "and64", (c) => c.write.execAnd64([itA, itB])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), a & b),
        },
        {
          label: "or64",
          send: () => runPodRoundTrip(ctx, "or64", (c) => c.write.execOr64([itA, itB])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), a | b),
        },
        {
          label: "xor64",
          send: () => runPodRoundTrip(ctx, "xor64", (c) => c.write.execXor64([itA, itB])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), a ^ b),
        },
        {
          label: "min64",
          send: () => runPodRoundTrip(ctx, "min64", (c) => c.write.execMin64([itA, itB])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), a < b ? a : b),
        },
        {
          label: "max64",
          send: () => runPodRoundTrip(ctx, "max64", (c) => c.write.execMax64([itA, itB])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), a > b ? a : b),
        },
        {
          label: "gt64",
          send: () => runPodRoundTrip(ctx, "gt64", (c) => c.write.execGt64([itB, itA])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), 1n),
        },
        {
          label: "eq64",
          send: () => runPodRoundTrip(ctx, "eq64", (c) => c.write.execEq64([itA, itEq])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), 0n),
        },
        {
          label: "mux64_1",
          send: () => runPodRoundTrip(ctx, "mux64_1", (c) => c.write.execMux64([itOne, itA, itB])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), a),
        },
        {
          label: "mux64_0",
          send: () => runPodRoundTrip(ctx, "mux64_0", (c) => c.write.execMux64([itZero, itA, itB])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), b),
        },
        {
          label: "shl64",
          send: () => runPodRoundTrip(ctx, "shl64", (c) => c.write.execShl64([itA, 2])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), a << 2n),
        },
        {
          label: "shr64",
          send: () => runPodRoundTrip(ctx, "shr64", (c) => c.write.execShr64([itB, 2])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), b >> 2n),
        },
        {
          label: "randBoundedBits64",
          send: () => runPodRoundTrip(ctx, "randBounded", (c) => c.write.execRandBoundedBits64([5])),
          check: (raw) => {
            const v = decodePodPlainUint256(raw);
            assert.ok(v < 32n);
          },
        },
      ];

      for (const row of filterPodOpsRows(rows)) {
        logStep(`PodTest64: ${row.label}`);
        const raw = await row.send();
        row.check(raw);
      }

      if (podOpsRowEnabled("rand64")) {
        logStep("PodTest64: rand64 (plaintext uint256 payload)");
        const randRaw = await runPodRoundTrip(ctx, "rand64", (c) => c.write.execRand64());
        const rv = decodePodPlainUint256(randRaw);
        assert.ok(rv >= 0n && rv < 1n << 64n);
      }
    });
  });

  const d128 = podOpsSuiteEnabled("PodTest128") ? describe : describe.skip;
  d128("PodTest128", function () {
    let ctx: PodTestContext;

    before(async function () {
      process.env.COTI_REUSE_CONTRACTS = "true";
      ctx = await setupPodTestContext({
        sepoliaViem,
        cotiViem,
        podContractName: "PodTest128",
        forceRedeployCotiExecutor: takePodOpsCotiExecutorRefresh(),
      });
    });

    it("runs table of 128-bit ops", async function () {
      const a = (1n << 80n) + 15n;
      const b = (1n << 80n) + 27n;
      const itA = await buildEncryptedInput128(ctx, a);
      const itB = await buildEncryptedInput128(ctx, b);
      // `checkedMul` must not overflow uint128: keep product within 2^128-1 (e.g. two ~60-bit factors).
      const mulA = (1n << 60n) + 15n;
      const mulB = (1n << 60n) + 27n;
      const itMulA = await buildEncryptedInput128(ctx, mulA);
      const itMulB = await buildEncryptedInput128(ctx, mulB);
      const itOne = await buildEncryptedBool(ctx, 1);
      const itZero = await buildEncryptedBool(ctx, 0);

      const rows: Array<{
        label: string;
        send: () => Promise<`0x${string}`>;
        check: (raw: `0x${string}`) => void;
      }> = [
        {
          label: "add128",
          send: () => runPodRoundTrip(ctx, "add128", (c) => c.write.execAdd128([itA, itB])),
          check: (raw) => assert.equal(decryptU128Payload(raw, ctx.crypto.userKey), a + b),
        },
        {
          label: "sub128",
          send: () => runPodRoundTrip(ctx, "sub128", (c) => c.write.execSub128([itB, itA])),
          check: (raw) => assert.equal(decryptU128Payload(raw, ctx.crypto.userKey), b - a),
        },
        {
          label: "mul128",
          send: () => runPodRoundTrip(ctx, "mul128", (c) => c.write.execMul128([itMulA, itMulB])),
          check: (raw) => assert.equal(decryptU128Payload(raw, ctx.crypto.userKey), mulA * mulB),
        },
        {
          label: "gt128",
          send: () => runPodRoundTrip(ctx, "gt128", (c) => c.write.execGt128([itB, itA])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), 1n),
        },
        {
          label: "mux128",
          send: () => runPodRoundTrip(ctx, "mux128", (c) => c.write.execMux128([itOne, itA, itB])),
          check: (raw) => assert.equal(decryptU128Payload(raw, ctx.crypto.userKey), a),
        },
        {
          label: "mux128b",
          send: () => runPodRoundTrip(ctx, "mux128b", (c) => c.write.execMux128([itZero, itA, itB])),
          check: (raw) => assert.equal(decryptU128Payload(raw, ctx.crypto.userKey), b),
        },
        {
          label: "shl128",
          send: () => runPodRoundTrip(ctx, "shl128", (c) => c.write.execShl128([itA, 3])),
          check: (raw) => assert.equal(decryptU128Payload(raw, ctx.crypto.userKey), a << 3n),
        },
        {
          label: "randBoundedBits128",
          send: () => runPodRoundTrip(ctx, "rb128", (c) => c.write.execRandBoundedBits128([9])),
          check: (raw) => {
            const v = decodePodPlainUint256(raw);
            assert.ok(v < 512n);
          },
        },
      ];

      for (const row of filterPodOpsRows(rows)) {
        logStep(`PodTest128: ${row.label}`);
        row.check(await row.send());
      }

      if (podOpsRowEnabled("rand128")) {
        logStep("PodTest128: rand128 (plaintext)");
        const rraw = await runPodRoundTrip(ctx, "rand128", (c) => c.write.execRand128());
        const rv = decodePodPlainUint256(rraw);
        assert.ok(rv >= 0n && rv < 1n << 128n);
      }
    });
  });

  const d256 = podOpsSuiteEnabled("PodTest256") ? describe : describe.skip;
  d256("PodTest256", function () {
    let ctx: PodTestContext;

    before(async function () {
      process.env.COTI_REUSE_CONTRACTS = "true";
      ctx = await setupPodTestContext({
        sepoliaViem,
        cotiViem,
        podContractName: "PodTest256",
        forceRedeployCotiExecutor: takePodOpsCotiExecutorRefresh(),
      });
    });

    it("runs table of 256-bit ops", async function () {
      const a = (1n << 200n) + 11n;
      const b = (1n << 200n) + 3n;
      const itA = await buildEncryptedInput256(ctx, a);
      const itB = await buildEncryptedInput256(ctx, b);
      // `checkedMul` must fit in uint256: (2^120)^2 = 2^240 < 2^256.
      const mulA = (1n << 120n) + 11n;
      const mulB = (1n << 120n) + 3n;
      const itMulA = await buildEncryptedInput256(ctx, mulA);
      const itMulB = await buildEncryptedInput256(ctx, mulB);
      const itOne = await buildEncryptedBool(ctx, 1);

      const rows: Array<{
        label: string;
        send: () => Promise<`0x${string}`>;
        check: (raw: `0x${string}`) => void;
      }> = [
        {
          label: "add256",
          send: () => runPodRoundTrip(ctx, "add256", (c) => c.write.execAdd256([itA, itB])),
          check: (raw) => assert.equal(decryptU256Payload(raw, ctx.crypto.userKey), a + b),
        },
        {
          label: "sub256",
          send: () => runPodRoundTrip(ctx, "sub256", (c) => c.write.execSub256([itA, itB])),
          check: (raw) => assert.equal(decryptU256Payload(raw, ctx.crypto.userKey), a - b),
        },
        {
          label: "mul256",
          send: () => runPodRoundTrip(ctx, "mul256", (c) => c.write.execMul256([itMulA, itMulB])),
          check: (raw) => assert.equal(decryptU256Payload(raw, ctx.crypto.userKey), mulA * mulB),
        },
        {
          label: "gt256",
          send: () => runPodRoundTrip(ctx, "gt256", (c) => c.write.execGt256([itA, itB])),
          check: (raw) => assert.equal(decryptU64Payload(raw, ctx.crypto.userKey), 1n),
        },
        {
          label: "mux256",
          send: () => runPodRoundTrip(ctx, "mux256", (c) => c.write.execMux256([itOne, itA, itB])),
          check: (raw) => assert.equal(decryptU256Payload(raw, ctx.crypto.userKey), a),
        },
        {
          label: "randBoundedBits256",
          send: () => runPodRoundTrip(ctx, "rb256", (c) => c.write.execRandBoundedBits256([10])),
          check: (raw) => {
            const v = decodePodPlainUint256(raw);
            assert.ok(v < 1024n);
          },
        },
      ];

      for (const row of filterPodOpsRows(rows)) {
        logStep(`PodTest256: ${row.label}`);
        row.check(await row.send());
      }

      if (podOpsRowEnabled("rand256")) {
        logStep("PodTest256: rand256 (plaintext)");
        const rraw = await runPodRoundTrip(ctx, "rand256", (c) => c.write.execRand256());
        const rv = decodePodPlainUint256(rraw);
        assert.ok(rv >= 0n);
      }
    });
  });
});
