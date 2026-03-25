import assert from "node:assert/strict";
import { JsonRpcProvider } from "ethers";
import { privateKeyToAccount } from "viem/accounts";
import { decryptUint } from "@coti-io/coti-sdk-typescript";
import { ONBOARD_CONTRACT_ADDRESS, transferNative, Wallet as CotiWallet } from "@coti-io/coti-ethers";
import {
  buildEncryptedInput256,
  decryptUint256,
  logStep,
  normalizePrivateKey,
  onboardUser,
  receiptWaitOptions,
  requireEnv,
  requirePrivateKey,
  runCrossChainTwoWayRoundTrip,
  setupContext,
  type MineRequestOptions,
  type TestContext,
} from "../system/mpc-test-utils.js";

/**
 * Gas for COTI `batchProcessRequests` in pod-token tests (`syncBalances` runs `offBoardToUser` per account in one tx).
 * Default is above wide MPC default to reduce OOG on testnet; override with `COTI_MINE_GAS_POD_TOKEN`.
 */
const DEFAULT_COTI_MINE_GAS_POD_TOKEN = 80_000_000n;

export function getDefaultCotiMineGasPodToken(): bigint {
  const raw = process.env.COTI_MINE_GAS_POD_TOKEN?.trim();
  if (!raw) return DEFAULT_COTI_MINE_GAS_POD_TOKEN;
  try {
    return BigInt(raw);
  } catch {
    return DEFAULT_COTI_MINE_GAS_POD_TOKEN;
  }
}

export type PodTokenTestContext = {
  base: TestContext;
  pod: any;
  /** Same Hardhat `PodERC20` instance, wallet = COTI-funded owner (cross-chain test pattern). */
  podAsCoti: any;
  podCotiSide: any;
  owner: `0x${string}`;
  bob: { address: `0x${string}`; userKey: string; wallet: CotiWallet };
};

const deriveSecondaryPrivateKey = (primaryKey: string) => {
  const normalized = normalizePrivateKey(primaryKey).slice(2);
  const bytes = Buffer.from(normalized, "hex");
  bytes[bytes.length - 1] ^= 0x01;
  return `0x${bytes.toString("hex")}`;
};

/** Funds and onboards a second account (Bob) for balance decryption on transfers. */
export async function setupBobUser(primaryPrivateKey: string): Promise<{
  address: `0x${string}`;
  userKey: string;
  wallet: CotiWallet;
}> {
  const cotiRpcUrl = requireEnv("COTI_TESTNET_RPC_URL");
  const onboardAddress = process.env.COTI_ONBOARD_CONTRACT_ADDRESS || ONBOARD_CONTRACT_ADDRESS;
  const normalizedKey = deriveSecondaryPrivateKey(primaryPrivateKey);
  const provider = new JsonRpcProvider(cotiRpcUrl) as any;
  const fundingWallet = new CotiWallet(normalizePrivateKey(primaryPrivateKey), provider);
  const wallet = new CotiWallet(normalizedKey, provider);

  const balance = await provider.getBalance(wallet.address);
  const minBalance = 300_000_000_000_000_000n;
  if (balance < minBalance) {
    logStep("Funding Bob for COTI onboarding");
    let funded = false;
    for (let attempt = 0; attempt < 4 && !funded; attempt++) {
      if (attempt > 0) {
        logStep(`Bob funding retry ${attempt} (nonce / fee)`);
        await new Promise((r) => setTimeout(r, 5_000));
      }
      try {
        const tx = await transferNative(
          provider,
          fundingWallet,
          wallet.address,
          1_000_000_000_000_000_000n,
          100_000
        );
        funded = !!tx;
      } catch (e) {
        logStep(`Bob funding attempt failed: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
    if (!funded) {
      throw new Error("Failed to fund Bob after retries.");
    }
  }

  const fundedBalance = await provider.getBalance(wallet.address);
  if (fundedBalance < minBalance) {
    throw new Error(`Bob balance still too low: ${fundedBalance}`);
  }

  const userKey = await onboardUser(normalizedKey, cotiRpcUrl, onboardAddress, "COTI_AES_KEY_BOB");
  wallet.setAesKey(userKey);
  return { address: wallet.address as `0x${string}`, userKey, wallet };
}

/** Inbox + miners + `PodERC20` on Hardhat + `PodErc20CotiSide` on COTI with mutual authorization. */
export async function setupPodTokenTestContext(params: {
  sepoliaViem: any;
  cotiViem: any;
}): Promise<PodTokenTestContext> {
  const base = await setupContext(params);

  const cotiPk = normalizePrivateKey(requirePrivateKey("COTI_TESTNET_PRIVATE_KEY"));
  const cotiAccount = privateKeyToAccount(cotiPk as `0x${string}`);
  const owner = cotiAccount.address;
  const hardhatCotiWallet = await params.sepoliaViem.getWalletClient(owner);

  logStep("Deploying PodErc20CotiSide on COTI");
  const podCotiSide = await params.cotiViem.deployContract(
    "PodErc20CotiSide",
    [base.contracts.inboxCoti.address, owner],
    { client: { public: base.coti.publicClient, wallet: base.coti.wallet } } as any
  );

  logStep("Deploying PodERC20 on Hardhat");
  const pod = await params.sepoliaViem.deployContract("PodERC20", [
    base.chainIds.coti,
    base.contracts.inboxSepolia.address,
    podCotiSide.address,
    "PoD Test Token",
    "PODT",
  ]);

  await podCotiSide.write.setAuthorizedRemote([BigInt(base.chainIds.sepolia), pod.address]);

  const podAsCoti = await params.sepoliaViem.getContractAt("PodERC20", pod.address, {
    client: { public: base.sepolia.publicClient, wallet: hardhatCotiWallet },
  });

  const bob = await setupBobUser(cotiPk);

  logStep("Pod token setup complete");
  return { base, pod, podAsCoti, podCotiSide, owner, bob };
}

/** Owner `mint(to, amount)` on `PodErc20CotiSide` (COTI balance ciphertext ledger). Waits for confirmation. */
export async function mintOnCoti(
  ctx: PodTokenTestContext,
  to: `0x${string}`,
  amount: bigint
): Promise<void> {
  const txHash = await ctx.podCotiSide.write.mint([to, amount]);
  await ctx.base.coti.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
}

/** Runs `syncBalances` from PoD and completes COTI + Hardhat mining (pulls ciphertext to Sepolia). */
export async function syncPodBalancesRoundTrip(
  ctx: PodTokenTestContext,
  accounts: readonly `0x${string}`[],
  label: string,
  mineOptions?: MineRequestOptions
): Promise<ReturnType<typeof runCrossChainTwoWayRoundTrip>> {
  const txHash = await ctx.podAsCoti.write.syncBalances([[...accounts]]);
  await ctx.base.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
  return runCrossChainTwoWayRoundTrip(ctx.base, label, {
    ...mineOptions,
    gas: mineOptions?.gas ?? getDefaultCotiMineGasPodToken(),
  });
}

/**
 * Sends a PoD-side two-way tx (`transfer`, `approve`, …), then mines COTI and the return leg on Hardhat.
 */
export async function completePodOpRoundTrip(
  ctx: PodTokenTestContext,
  label: string,
  send: () => Promise<`0x${string}`>,
  mineOptions?: MineRequestOptions
): Promise<ReturnType<typeof runCrossChainTwoWayRoundTrip>> {
  const txHash = await send();
  await ctx.base.sepolia.publicClient.waitForTransactionReceipt({ hash: txHash, ...receiptWaitOptions });
  return runCrossChainTwoWayRoundTrip(ctx.base, label, {
    ...mineOptions,
    gas: mineOptions?.gas ?? getDefaultCotiMineGasPodToken(),
  });
}

export function userKeyForAccount(ctx: PodTokenTestContext, account: `0x${string}`): string {
  if (account.toLowerCase() === ctx.owner.toLowerCase()) {
    return ctx.base.crypto.userKey;
  }
  if (account.toLowerCase() === ctx.bob.address.toLowerCase()) {
    return ctx.bob.userKey;
  }
  throw new Error(`No AES key configured for ${account}`);
}

/** Decrypts `PodERC20.balanceOf(account)` using the matching onboarded user key. */
export async function readDecryptedBalance(
  ctx: PodTokenTestContext,
  account: `0x${string}`
): Promise<bigint> {
  const ct = await ctx.pod.read.balanceOf([account]);
  return decryptUint256(ct, userKeyForAccount(ctx, account), decryptUint);
}

/** Reads `balanceOfWithStatus` and returns `{ balance, pending }`. */
export async function readBalanceWithPending(
  ctx: PodTokenTestContext,
  account: `0x${string}`
): Promise<{ balance: bigint; pending: boolean }> {
  const [ct, pending] = await ctx.pod.read.balanceOfWithStatus([account]);
  const balance = await decryptUint256(ct, userKeyForAccount(ctx, account), decryptUint);
  return { balance, pending };
}

export async function readDecryptedAllowance(
  ctx: PodTokenTestContext,
  owner: `0x${string}`,
  spender: `0x${string}`
): Promise<{ ownerCt: bigint; spenderCt: bigint }> {
  const allowance = await ctx.pod.read.allowance([owner, spender]);
  const ownerCt = getAllowanceHalf(allowance, "owner");
  const spenderCt = getAllowanceHalf(allowance, "spender");
  const ownerKey = userKeyForAccount(ctx, owner);
  const spenderKey = userKeyForAccount(ctx, spender);
  return {
    ownerCt: decryptUint256(ownerCt, ownerKey, decryptUint),
    spenderCt: decryptUint256(spenderCt, spenderKey, decryptUint),
  };
}

function getAllowanceHalf(allowance: unknown, role: "owner" | "spender"): unknown {
  const field = role === "owner" ? "ownerCiphertext" : "spenderCiphertext";
  const tuple = allowance as Record<string, unknown>;
  return tuple[field] ?? tuple[role === "owner" ? 0 : 1];
}

export async function readAllowanceWithPending(
  ctx: PodTokenTestContext,
  owner: `0x${string}`,
  spender: `0x${string}`
): Promise<{ ownerPart: bigint; spenderPart: bigint; pending: boolean }> {
  const [allowance, pending] = await ctx.pod.read.allowanceWithStatus([owner, spender]);
  const ownerCt = getAllowanceHalf(allowance, "owner");
  const spenderCt = getAllowanceHalf(allowance, "spender");
  return {
    ownerPart: decryptUint256(ownerCt, userKeyForAccount(ctx, owner), decryptUint),
    spenderPart: decryptUint256(spenderCt, userKeyForAccount(ctx, spender), decryptUint),
    pending,
  };
}

/** `buildEncryptedInput256` against the shared test encrypt context. */
export function encryptAmount(ctx: PodTokenTestContext, amount: bigint) {
  return buildEncryptedInput256(ctx.base, amount);
}

/** UTF-8 string from revert / raise payload bytes returned by `failedRequests`. */
export function utf8FromFailedRequestBytes(hex: `0x${string}`): string {
  if (!hex || hex === "0x") {
    return "";
  }
  const slice = hex.startsWith("0x") ? hex.slice(2) : hex;
  return Buffer.from(slice, "hex").toString("utf8");
}

/**
 * Mints on COTI then syncs listed accounts to PoD (one round trip).
 * Convenience for tests that start from a funded COTI ledger.
 */
export async function mintOnCotiAndSync(
  ctx: PodTokenTestContext,
  recipients: readonly { address: `0x${string}`; amount: bigint }[],
  label: string,
  mineOptions?: MineRequestOptions
): Promise<ReturnType<typeof runCrossChainTwoWayRoundTrip>> {
  for (const { address, amount } of recipients) {
    await mintOnCoti(ctx, address, amount);
  }
  const accounts = recipients.map((r) => r.address);
  return syncPodBalancesRoundTrip(ctx, accounts, label, mineOptions);
}

/** Mines the latest queued PoD→COTI message without sending a new PoD tx (e.g. clear a pending transfer). */
export async function mineLatestOutboundRoundTrip(
  ctx: PodTokenTestContext,
  label: string,
  mineOptions?: MineRequestOptions
): Promise<ReturnType<typeof runCrossChainTwoWayRoundTrip>> {
  return runCrossChainTwoWayRoundTrip(ctx.base, label, {
    ...mineOptions,
    gas: mineOptions?.gas ?? getDefaultCotiMineGasPodToken(),
  });
}

export function assertIncludesInsensitive(haystack: string, needle: string) {
  assert.ok(
    haystack.toLowerCase().includes(needle.toLowerCase()),
    `expected ${JSON.stringify(haystack)} to include ${JSON.stringify(needle)}`
  );
}
