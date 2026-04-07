import fs from "node:fs/promises";
import path from "node:path";
import { network } from "hardhat";
import { zeroAddress } from "viem";
import {
  appendDeploymentLog,
  asAddress,
  configureTestnetInboxMinFees,
  deployAndWireTestnetPriceOracle,
  getChainConfig,
  getViemClients,
  isTestnetSepoliaCotiPairChain,
  readDeployConfig,
  requireEnv,
  resolveDeployerAddress,
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

  const deployer = await resolveDeployerAddress(walletClient);
  const writeOpts = { account: deployer } as const;

  const currentOracle = await inbox.read.priceOracle();
  let priceOracleAddress: `0x${string}`;

  if (currentOracle !== zeroAddress) {
    console.log(`[deploy-inbox] priceOracle already set (${currentOracle}), skip wiring`);
    priceOracleAddress = currentOracle;
  } else {
    const fromConfig = existingChainConfig.priceOracle?.trim();
    const presetRaw =
      fromConfig && fromConfig.startsWith("0x") && fromConfig.length === 42 ? fromConfig : undefined;

    if (presetRaw) {
      const preset = asAddress(presetRaw, "deployConfig.json chains[chainId].priceOracle");
      console.log(`[deploy-inbox] Wiring PriceOracle from deployConfig.json: ${preset}`);
      await inbox.write.setPriceOracle([preset], writeOpts);
      priceOracleAddress = preset;
    } else {
      console.log("[deploy-inbox] Deploying PriceOracle and wiring inbox...");
      const priceOracle = await deployAndWireTestnetPriceOracle({
        viem,
        publicClient,
        walletClient,
        chainId,
        inbox,
      });
      priceOracleAddress = priceOracle.address;
      console.log(`[deploy-inbox] PriceOracle deployed and set on inbox: ${priceOracleAddress}`);
    }
  }

  const oracleForLog = await viem.getContractAt("PriceOracle", priceOracleAddress, {
    client: { public: publicClient, wallet: walletClient },
  });
  const [localUsd, remoteUsd] = await oracleForLog.read.getPricesUSD();
  console.log(`[deploy-inbox] Oracle getPricesUSD (18-dec): local=${localUsd} remote=${remoteUsd}`);

  if (isTestnetSepoliaCotiPairChain(chainId)) {
    console.log("[deploy-inbox] Applying testnet min fee configs (local=this chain, remote=paired chain)…");
    await configureTestnetInboxMinFees({
      inbox,
      publicClient,
      walletClient,
      chainId,
    });
  } else {
    console.log(
      `[deploy-inbox] Skipping testnet min fee configs (chainId=${chainId} not Sepolia/COTI/local 31337)`
    );
  }

  console.log("[deploy-inbox] Writing deployment log entry");
  await appendDeploymentLog({
    contract: "Inbox",
    address: inbox.address,
    chainId,
    network: networkLabel,
  });
  await appendDeploymentLog({
    contract: "PriceOracle",
    address: priceOracleAddress,
    chainId,
    network: networkLabel,
  });

  existingChainConfig.inbox = inbox.address;
  existingChainConfig.priceOracle = priceOracleAddress;
  await fs.writeFile(deployConfigPath, `${JSON.stringify(deployConfig, null, 2)}\n`, "utf8");
  console.log("[deploy-inbox] Updated deployConfig.json");

  console.log("[deploy-inbox] Done");
};

main().catch((error) => {
  console.error("[deploy-inbox] Failed:", error);
  process.exitCode = 1;
});
