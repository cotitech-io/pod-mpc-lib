import { network } from "hardhat";
import {
  appendDeploymentLog,
  asAddress,
  getChainConfig,
  getViemClients,
  podConfigureKeepInbox,
  readDeployConfig,
  requireEnv,
} from "./deploy-utils.js";

const COTI_TESTNET_CHAIN_ID = 7082400n;
const COTI_MAINNET_CHAIN_ID = 2632500n;

const main = async () => {
  console.log("[deploy-private-treasury-approval] Connecting to network from CLI");
  const connection = await network.connect();
  const { viem, provider, networkName } = connection;
  const { chainId, chainName, publicClient, walletClient } = await getViemClients(
    viem,
    provider,
    networkName
  );
  const networkLabel = chainName ?? "unknown";
  console.log(`[deploy-private-treasury-approval] Connected: chainId=${chainId} network=${networkLabel}`);

  const deployConfig = await readDeployConfig();
  const sourceChainConfig = getChainConfig(deployConfig, chainId, "source");
  const inboxAddress = asAddress(sourceChainConfig.inbox ?? "", `deployConfig.chains.${chainId}.inbox`);
  const cotiChainId = chainId === 1 ? COTI_MAINNET_CHAIN_ID : COTI_TESTNET_CHAIN_ID;
  const remoteAddress = asAddress(
    requireEnv("PRIVATE_TREASURY_APPROVAL_COTI_ADDRESS"),
    "PRIVATE_TREASURY_APPROVAL_COTI_ADDRESS"
  );
  console.log(`[deploy-private-treasury-approval] Inbox=${inboxAddress}`);
  console.log(
    `[deploy-private-treasury-approval] PrivateTreasuryApprovalCoti=${remoteAddress} cotiChainId=${cotiChainId}`
  );

  console.log("[deploy-private-treasury-approval] Deploying PrivateTreasuryApproval...");
  const treasury = await viem.deployContract("PrivateTreasuryApproval", [inboxAddress], {
    client: { public: publicClient, wallet: walletClient },
  });
  console.log(
    `[deploy-private-treasury-approval] PrivateTreasuryApproval deployed: ${treasury.address}`
  );

  console.log("[deploy-private-treasury-approval] Configuring PrivateTreasuryApproval...");
  await treasury.write.configure(
    podConfigureKeepInbox(remoteAddress, cotiChainId)
  );
  console.log("[deploy-private-treasury-approval] PrivateTreasuryApproval configured");

  console.log("[deploy-private-treasury-approval] Writing deployment log entry");
  await appendDeploymentLog({
    contract: "PrivateTreasuryApproval",
    address: treasury.address,
    chainId,
    network: networkLabel,
  });
  console.log("[deploy-private-treasury-approval] Done");
};

main().catch((error) => {
  console.error("[deploy-private-treasury-approval] Failed:", error);
  process.exitCode = 1;
});
