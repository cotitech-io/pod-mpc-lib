import { network } from "hardhat";
import {
  appendDeploymentLog,
  asAddress,
  getChainConfig,
  getViemClients,
  readDeployConfig,
} from "./deploy-utils.js";

const main = async () => {
  console.log("[deploy-private-treasury-approval-coti] Connecting to network from CLI");
  const connection = await network.connect();
  const { viem, provider, networkName } = connection;
  const { chainId, chainName, publicClient, walletClient } = await getViemClients(
    viem,
    provider,
    networkName
  );
  const networkLabel = chainName ?? "unknown";
  console.log(
    `[deploy-private-treasury-approval-coti] Connected: chainId=${chainId} network=${networkLabel}`
  );

  const deployConfig = await readDeployConfig();
  const cotiChainConfig = getChainConfig(deployConfig, chainId, "coti");
  const inboxAddress = asAddress(cotiChainConfig.inbox ?? "", `deployConfig.chains.${chainId}.inbox`);
  console.log(`[deploy-private-treasury-approval-coti] Inbox=${inboxAddress}`);

  console.log("[deploy-private-treasury-approval-coti] Deploying PrivateTreasuryApprovalCoti...");
  const treasuryCoti = await viem.deployContract("PrivateTreasuryApprovalCoti", [inboxAddress], {
    client: { public: publicClient, wallet: walletClient },
  });
  console.log(
    `[deploy-private-treasury-approval-coti] PrivateTreasuryApprovalCoti deployed: ${treasuryCoti.address}`
  );

  console.log("[deploy-private-treasury-approval-coti] Writing deployment log entry");
  await appendDeploymentLog({
    contract: "PrivateTreasuryApprovalCoti",
    address: treasuryCoti.address,
    chainId,
    network: networkLabel,
  });
  console.log("[deploy-private-treasury-approval-coti] Done");
};

main().catch((error) => {
  console.error("[deploy-private-treasury-approval-coti] Failed:", error);
  process.exitCode = 1;
});
