import fs from "node:fs/promises";
import path from "node:path";
import { defineChain, parseUnits, zeroAddress, type PublicClient, type WalletClient } from "viem";

/** Await mining so the next `write` does not reuse a nonce still pending on COTI (replacement transaction underpriced). */
export const waitMined = async (publicClient: unknown, hash: `0x${string}`) => {
  const receipt = await (publicClient as PublicClient).waitForTransactionReceipt({
    hash,
    timeout: 300_000,
    pollingInterval: 2_000,
  });
  if (receipt.status !== "success") {
    throw new Error(`Transaction ${hash} reverted (status=${receipt.status})`);
  }
  return receipt;
};

/** Enough gas for `PriceOracle` admin price sets on COTI (large uint256 args can underestimate). */
const ORACLE_PRICE_WRITE_GAS = 500_000n;

/** Args for {PodUser.configure} when the inbox was already set in the constructor (`inbox_ == address(0)` skips inbox). */
export const podConfigureKeepInbox = (
  mpcExecutor: `0x${string}`,
  cotiChainId: bigint
): readonly [`0x${string}`, `0x${string}`, bigint] => [zeroAddress, mpcExecutor, cotiChainId];

type DeploymentLogEntry = {
  contract: string;
  address: `0x${string}`;
  chainId: number;
  network: string;
};

const logPath = path.resolve(process.cwd(), "deployment.log");
const deployConfigPath = path.resolve(process.cwd(), "deployConfig.json");

type DeployConfig = {
  chains: Record<
    string,
    {
      inbox?: string;
      cotiExecutor?: string;
      priceOracle?: string;
    }
  >;
};

/** Fixed testnet spot prices (USD per whole 18‑decimal native token). Used as {PriceOracle} 18‑decimal fixed values. */
export const TESTNET_ETH_USD = "2103.41";
export const TESTNET_COTI_USD = "0.01286";

/** USD per 1 whole token (18 decimals), matching {PriceOracle.PRICE_SCALE}. */
export const usdPerWholeToken18 = (usdWholeToken: string): bigint => parseUnits(usdWholeToken, 18);

/** @deprecated Use {@link usdPerWholeToken18}. Kept for tests and scripts that still import the old name. */
export const usdPerTokenWeiX128 = (usdWholeToken: string): bigint => usdPerWholeToken18(usdWholeToken);

export type OracleUsdLegs = { localUsd18: bigint; remoteUsd18: bigint };

/** @deprecated Use {@link oracleUsdPricesForChain} */
export type OracleLegs = OracleUsdLegs;

/**
 * Local = this chain's native token; remote = the paired chain's native token.
 * Sepolia / local Hardhat: local ETH, remote COTI. COTI testnet: local COTI, remote ETH.
 */
export const oracleUsdPricesForChain = (chainId: number): OracleUsdLegs => {
  const eth = usdPerWholeToken18(TESTNET_ETH_USD);
  const coti = usdPerWholeToken18(TESTNET_COTI_USD);
  const cotiTestnetId = Number(process.env.COTI_TESTNET_CHAIN_ID || "7082400");
  if (chainId === 11155111 || chainId === 31337) {
    return { localUsd18: eth, remoteUsd18: coti };
  }
  if (chainId === cotiTestnetId) {
    return { localUsd18: coti, remoteUsd18: eth };
  }
  throw new Error(
    `Unsupported chainId ${chainId} for testnet oracle legs. ` +
      `Use Sepolia (11155111), COTI testnet (${cotiTestnetId}), or local (31337), ` +
      `or set COTI_TESTNET_CHAIN_ID to match this network.`
  );
};

/** @deprecated Use {@link oracleUsdPricesForChain} */
export const oracleLegsForChain = (chainId: number): OracleUsdLegs => oracleUsdPricesForChain(chainId);

/**
 * Sepolia-side fee template (variable minimum): `constantFee == 0` and all template fields non-zero.
 * Used as **local** on Sepolia and as **remote** on COTI when paired with {@link FEE_CONFIG_COTI_SIDE}.
 */
export const FEE_CONFIG_SEPOLIA_SIDE = {
  constantFee: 0n,
  gasPerByte: 10n,
  callbackExecutionGas: 100_000n,
  errorLength: 300n,
  bufferRatioX10000: 5000n,
} as const;

/**
 * COTI-side fee template (constant minimum gas units): `constantFee > 0` and other fields zero.
 * Used as **remote** on Sepolia and as **local** on COTI when paired with {@link FEE_CONFIG_SEPOLIA_SIDE}.
 */
export const FEE_CONFIG_COTI_SIDE = {
  constantFee: 12_000_000n,
  gasPerByte: 0n,
  callbackExecutionGas: 0n,
  errorLength: 0n,
  bufferRatioX10000: 0n,
} as const;

export type FeeConfigTuple = {
  constantFee: bigint;
  gasPerByte: bigint;
  callbackExecutionGas: bigint;
  errorLength: bigint;
  bufferRatioX10000: bigint;
};

/**
 * Minimum fee templates for this inbox: **local** = this chain's native leg, **remote** = the paired chain's leg.
 * Sepolia: local ETH (variable), remote COTI (constant). COTI: local COTI (constant), remote ETH (variable).
 */
export const testnetMinFeeConfigsForChain = (chainId: number): { local: FeeConfigTuple; remote: FeeConfigTuple } => {
  const cotiTestnetId = Number(process.env.COTI_TESTNET_CHAIN_ID || "7082400");
  if (chainId === 11155111 || chainId === 31337) {
    return { local: { ...FEE_CONFIG_SEPOLIA_SIDE }, remote: { ...FEE_CONFIG_COTI_SIDE } };
  }
  if (chainId === cotiTestnetId) {
    return { local: { ...FEE_CONFIG_COTI_SIDE }, remote: { ...FEE_CONFIG_SEPOLIA_SIDE } };
  }
  throw new Error(
    `Unsupported chainId ${chainId} for testnet fee configs. ` +
      `Use Sepolia (11155111), COTI testnet (${cotiTestnetId}), or local (31337), ` +
      `or set COTI_TESTNET_CHAIN_ID to match this network.`
  );
};

/** True for Sepolia, local Hardhat, or COTI testnet (same IDs as {@link testnetMinFeeConfigsForChain}). */
export const isTestnetSepoliaCotiPairChain = (chainId: number): boolean => {
  const cotiTestnetId = Number(process.env.COTI_TESTNET_CHAIN_ID || "7082400");
  return chainId === 11155111 || chainId === 31337 || chainId === cotiTestnetId;
};

/** Address that will sign txs for this wallet (must match constructor `initialOwner` for oracle admin calls). */
export const resolveDeployerAddress = async (walletClient: WalletClient): Promise<`0x${string}`> => {
  const fromAccount = walletClient.account?.address;
  if (fromAccount) {
    return fromAccount;
  }
  const addresses = await walletClient.getAddresses();
  const first = addresses[0];
  if (!first) {
    throw new Error("resolveDeployerAddress: wallet has no accounts");
  }
  return first;
};

type DeployOracleParams = {
  viem: any;
  publicClient: unknown;
  walletClient: WalletClient;
  chainId: number;
};

/**
 * Deploys `PriceOracle` and sets local/remote 18‑decimal USD prices from {@link oracleUsdPricesForChain}
 * (ETH/COTI spot from {@link TESTNET_ETH_USD} / {@link TESTNET_COTI_USD}). Does not touch an inbox.
 */
export const deployTestnetPriceOracle = async (params: DeployOracleParams) => {
  const { viem, publicClient, walletClient, chainId } = params;
  const deployer = await resolveDeployerAddress(walletClient);
  const writeOpts = { account: deployer, gas: ORACLE_PRICE_WRITE_GAS };
  const { localUsd18, remoteUsd18 } = oracleUsdPricesForChain(chainId);

  const oracle = await viem.deployContract("PriceOracle", [deployer], {
    client: { public: publicClient, wallet: walletClient },
    account: deployer,
  });

  const h1 = await oracle.write.setLocalTokenPriceUSD([localUsd18], writeOpts);
  await waitMined(publicClient, h1);
  const h2 = await oracle.write.setRemoteTokenPriceUSD([remoteUsd18], writeOpts);
  await waitMined(publicClient, h2);

  let localStored = await oracle.read.getLocalTokenPriceUSD();
  let remoteStored = await oracle.read.getRemoteTokenPriceUSD();
  if (localStored === 0n) {
    const h = await oracle.write.setLocalTokenPriceUSD([localUsd18], writeOpts);
    await waitMined(publicClient, h);
    localStored = await oracle.read.getLocalTokenPriceUSD();
  }
  if (remoteStored === 0n) {
    const h = await oracle.write.setRemoteTokenPriceUSD([remoteUsd18], writeOpts);
    await waitMined(publicClient, h);
    remoteStored = await oracle.read.getRemoteTokenPriceUSD();
  }
  if (localStored === 0n || remoteStored === 0n) {
    throw new Error(
      `PriceOracle legs not persisted (local=${localStored} remote=${remoteStored} chainId=${chainId})`
    );
  }

  return oracle as { address: `0x${string}`; read: { getPricesUSD: () => Promise<readonly [bigint, bigint]> } };
};

/**
 * Sets {@link InboxMiner.updateMinFeeConfigs} for the Sepolia↔COTI testnet pair (local = this chain, remote = paired chain).
 */
export const configureTestnetInboxMinFees = async (params: {
  inbox: {
    write: {
      updateMinFeeConfigs: (args: [FeeConfigTuple, FeeConfigTuple], options?: { account: `0x${string}` }) => Promise<`0x${string}`>;
    };
  };
  publicClient: unknown;
  walletClient: WalletClient;
  chainId: number;
}) => {
  const { local, remote } = testnetMinFeeConfigsForChain(params.chainId);
  const deployer = await resolveDeployerAddress(params.walletClient);
  const writeOpts = { account: deployer } as const;
  const hash = await params.inbox.write.updateMinFeeConfigs([local, remote], writeOpts);
  await waitMined(params.publicClient, hash);
};

/**
 * Deploys plain `PriceOracle`, seeds ETH/COTI legs from {@link oracleUsdPricesForChain}, and points the inbox at it.
 * Uses the same signer address for deploy and writes so `priceAdmin` (set in constructor) matches `msg.sender`.
 */
export const deployAndWireTestnetPriceOracle = async (
  params: DeployOracleParams & {
    inbox: {
      address: `0x${string}`;
      write: { setPriceOracle: (args: [`0x${string}`], options?: { account?: `0x${string}` }) => Promise<unknown> };
    };
  }
) => {
  const { walletClient, inbox } = params;
  const deployer = await resolveDeployerAddress(walletClient);
  const writeOpts = { account: deployer } as const;
  const oracle = await deployTestnetPriceOracle(params);
  const h = (await inbox.write.setPriceOracle([oracle.address], writeOpts)) as `0x${string}`;
  await waitMined(params.publicClient, h);
  return oracle;
};

export const requireEnv = (key: string): string => {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required env var: ${key}`);
  }
  return value;
};

export const optionalEnv = (key: string): string | undefined => process.env[key];

export const asAddress = (value: string, key: string): `0x${string}` => {
  if (!value.startsWith("0x") || value.length !== 42) {
    throw new Error(`Invalid ${key} address: ${value}`);
  }
  return value as `0x${string}`;
};

export const appendDeploymentLog = async (entry: DeploymentLogEntry) => {
  const payload = {
    timestamp: new Date().toISOString(),
    ...entry,
  };
  await fs.appendFile(logPath, `${JSON.stringify(payload)}\n`, "utf8");
};

export const readDeployConfig = async (): Promise<DeployConfig> => {
  const raw = await fs.readFile(deployConfigPath, "utf8");
  return JSON.parse(raw) as DeployConfig;
};

export const getChainConfig = (config: DeployConfig, chainId: number, label: string) => {
  const chainConfig = config.chains?.[String(chainId)];
  if (!chainConfig) {
    throw new Error(`Missing deploy config for chainId ${chainId} (${label}).`);
  }
  return chainConfig;
};

const resolveRpcUrl = (chainId: number) => {
  if (chainId === 7082400 && process.env.COTI_TESTNET_RPC_URL) {
    return process.env.COTI_TESTNET_RPC_URL;
  }
  if (chainId === 11155111 && process.env.SEPOLIA_RPC_URL) {
    return process.env.SEPOLIA_RPC_URL;
  }
  if (process.env.RPC_URL) {
    return process.env.RPC_URL;
  }
  return "http://127.0.0.1:8545";
};

export const getViemClients = async (
  viem: {
    getPublicClient: (config?: { chain?: any }) => Promise<any>;
    getWalletClients: (config?: { chain?: any }) => Promise<any[]>;
  },
  provider: { request: (args: { method: string }) => Promise<unknown> },
  networkName?: string
) => {
  const chainId = Number(await provider.request({ method: "eth_chainId" }));
  const rpcUrl = resolveRpcUrl(chainId);
  const chain = defineChain({
    id: chainId,
    name: networkName ?? `chain-${chainId}`,
    nativeCurrency: { name: "Native", symbol: "NATIVE", decimals: 18 },
    rpcUrls: { default: { http: [rpcUrl] }, public: { http: [rpcUrl] } },
  });

  const publicClient = await viem.getPublicClient({ chain });
  const [walletClient] = await viem.getWalletClients({ chain });

  return { chainId, chainName: chain.name, publicClient, walletClient };
};
