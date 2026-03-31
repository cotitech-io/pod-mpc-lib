import fs from "node:fs/promises";
import path from "node:path";
import { network } from "hardhat";
import {
  appendDeploymentLog,
  asAddress,
  deployAndWireTestnetPriceOracle,
  getChainConfig,
  getViemClients,
  readDeployConfig,
  requireEnv,
} from "./deploy-utils.js";

const deployConfigPath = path.resolve(process.cwd(), "deployConfig.json");

const main = async () => {
  console.log("[deploy-inbox] Connecting to network from CLI");
  const connection = await network.connect();
  const { viem, provider, networkName } = connection;
  const { chainId, chainName, publicClient, walletClient } = await getViemClients(
    viem,
    provider,
    networkName
  );
  const networkLabel = chainName ?? "unknown";
  const deployConfig = await readDeployConfig();
  const existingChainConfig = getChainConfig(deployConfig, chainId, "source");
  console.log(`[deploy-inbox] Connected: chainId=${chainId} network=${networkLabel}`);
  if (existingChainConfig.inbox) {
    console.log(`[deploy-inbox] Existing config inbox=${existingChainConfig.inbox}`);
  }
  const minerAddress = asAddress(requireEnv("MINER_ADDRESS"), "MINER_ADDRESS");
  console.log(`[deploy-inbox] Using miner: ${minerAddress}`);

  console.log("[deploy-inbox] Deploying Inbox...");
  const inbox = await viem.deployContract("Inbox", [0n], {
    client: { public: publicClient, wallet: walletClient },
  });
  console.log(`[deploy-inbox] Inbox deployed: ${inbox.address}`);
  console.log("[deploy-inbox] Adding miner...");
  await inbox.write.addMiner([minerAddress]);
  console.log("[deploy-inbox] Miner added");

  console.log("[deploy-inbox] Deploying PriceOracle and wiring inbox...");
  const priceOracle = await deployAndWireTestnetPriceOracle({
    viem,
    publicClient,
    walletClient,
    chainId,
    inbox,
  });
  console.log(`[deploy-inbox] PriceOracle deployed and set on inbox: ${priceOracle.address}`);

  console.log("[deploy-inbox] Writing deployment log entry");
  await appendDeploymentLog({
    contract: "Inbox",
    address: inbox.address,
    chainId,
    network: networkLabel,
  });
  await appendDeploymentLog({
    contract: "PriceOracle",
    address: priceOracle.address,
    chainId,
    network: networkLabel,
  });

  existingChainConfig.inbox = inbox.address;
  existingChainConfig.priceOracle = priceOracle.address;
  await fs.writeFile(deployConfigPath, `${JSON.stringify(deployConfig, null, 2)}\n`, "utf8");
  console.log("[deploy-inbox] Updated deployConfig.json");

  console.log("[deploy-inbox] Done");
};

main().catch((error) => {
  console.error("[deploy-inbox] Failed:", error);
  process.exitCode = 1;
});
