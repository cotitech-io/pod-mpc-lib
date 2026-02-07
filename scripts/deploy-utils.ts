import fs from "node:fs/promises";
import path from "node:path";
import { defineChain } from "viem";

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
    }
  >;
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
