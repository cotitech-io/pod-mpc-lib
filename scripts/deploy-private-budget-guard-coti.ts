import { network } from "hardhat";
import {
  appendDeploymentLog,
  asAddress,
  getChainConfig,
  getViemClients,
  readDeployConfig,
} from "./deploy-utils.js";

const main = async () => {
  console.log("[deploy-private-budget-guard-coti] Connecting to network from CLI");
  const connection = await network.connect();
  const { viem, provider, networkName } = connection;
  const { chainId, chainName, publicClient, walletClient } = await getViemClients(
    viem,
    provider,
    networkName
  );
  const networkLabel = chainName ?? "unknown";
  console.log(
    `[deploy-private-budget-guard-coti] Connected: chainId=${chainId} network=${networkLabel}`
  );

  const deployConfig = await readDeployConfig();
  const cotiChainConfig = getChainConfig(deployConfig, chainId, "coti");
  const inboxAddress = asAddress(cotiChainConfig.inbox ?? "", `deployConfig.chains.${chainId}.inbox`);
  console.log(`[deploy-private-budget-guard-coti] Inbox=${inboxAddress}`);

  console.log("[deploy-private-budget-guard-coti] Deploying PrivateBudgetGuardCoti...");
  const privateBudgetGuardCoti = await viem.deployContract("PrivateBudgetGuardCoti", [inboxAddress], {
    client: { public: publicClient, wallet: walletClient },
  });
  console.log(
    `[deploy-private-budget-guard-coti] PrivateBudgetGuardCoti deployed: ${privateBudgetGuardCoti.address}`
  );

  console.log("[deploy-private-budget-guard-coti] Writing deployment log entry");
  await appendDeploymentLog({
    contract: "PrivateBudgetGuardCoti",
    address: privateBudgetGuardCoti.address,
    chainId,
    network: networkLabel,
  });
  console.log("[deploy-private-budget-guard-coti] Done");
};

main().catch((error) => {
  console.error("[deploy-private-budget-guard-coti] Failed:", error);
  process.exitCode = 1;
});
