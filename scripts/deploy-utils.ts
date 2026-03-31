import fs from "node:fs/promises";
import path from "node:path";
import { defineChain, parseUnits, zeroAddress, type WalletClient } from "viem";

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

/** Matches {PriceOracle.PRICE_SCALE}. */
const PRICE_SCALE_X128 = 2n ** 128n;

/** Fixed testnet spot prices (USD per whole token; 18-decimal native on both legs). */
export const TESTNET_ETH_USD = "2103.41";
export const TESTNET_COTI_USD = "0.01286";

/** USD per 1 wei of an 18-decimal token, scaled by 2^128 (see `PriceOracle`). */
export const usdPerTokenWeiX128 = (usdWholeToken: string): bigint => {
  const p = parseUnits(usdWholeToken, 18);
  return (p * PRICE_SCALE_X128) / 10n ** 18n;
};

export type OracleLegs = { localX128: bigint; remoteX128: bigint };

/**
 * Local = this chain's native token; remote = the paired chain's native token.
 * Sepolia / local Hardhat: local ETH, remote COTI. COTI testnet: local COTI, remote ETH.
 */
export const oracleLegsForChain = (chainId: number): OracleLegs => {
  const eth = usdPerTokenWeiX128(TESTNET_ETH_USD);
  const coti = usdPerTokenWeiX128(TESTNET_COTI_USD);
  const cotiTestnetId = Number(process.env.COTI_TESTNET_CHAIN_ID || "7082400");
  if (chainId === 11155111 || chainId === 31337) {
    return { localX128: eth, remoteX128: coti };
  }
  if (chainId === cotiTestnetId) {
    return { localX128: coti, remoteX128: eth };
  }
  throw new Error(
    `Unsupported chainId ${chainId} for testnet oracle legs. ` +
      `Use Sepolia (11155111), COTI testnet (${cotiTestnetId}), or local (31337), ` +
      `or set COTI_TESTNET_CHAIN_ID to match this network.`
  );
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

/**
 * Deploys plain `PriceOracle`, seeds ETH/COTI legs from {@link oracleLegsForChain}, and points the inbox at it.
 * Uses the same signer address for deploy and writes so `priceAdmin` (set in constructor) matches `msg.sender`.
 */
export const deployAndWireTestnetPriceOracle = async (params: {
  viem: any;
  publicClient: unknown;
  walletClient: WalletClient;
  chainId: number;
  inbox: {
    address: `0x${string}`;
    write: { setPriceOracle: (args: [`0x${string}`], options?: { account?: `0x${string}` }) => Promise<unknown> };
  };
}) => {
  const { viem, publicClient, walletClient, chainId, inbox } = params;
  const deployer = await resolveDeployerAddress(walletClient);
  const writeOpts = { account: deployer } as const;
  const { localX128, remoteX128 } = oracleLegsForChain(chainId);

  const oracle = await viem.deployContract("PriceOracle", [deployer], {
    client: { public: publicClient, wallet: walletClient },
    account: deployer,
  });

  await oracle.write.setLocalTokenPriceUSDX128([localX128], writeOpts);
  await oracle.write.setRemoteTokenPriceUSDX128([remoteX128], writeOpts);
  await inbox.write.setPriceOracle([oracle.address], writeOpts);

  return oracle as { address: `0x${string}` };
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
