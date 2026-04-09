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
  console.log("[deploy-private-budget-guard] Connecting to network from CLI");
  const connection = await network.connect();
  const { viem, provider, networkName } = connection;
  const { chainId, chainName, publicClient, walletClient } = await getViemClients(
    viem,
    provider,
    networkName
  );
  const networkLabel = chainName ?? "unknown";
  console.log(`[deploy-private-budget-guard] Connected: chainId=${chainId} network=${networkLabel}`);

  const deployConfig = await readDeployConfig();
  const sourceChainConfig = getChainConfig(deployConfig, chainId, "source");
  const inboxAddress = asAddress(sourceChainConfig.inbox ?? "", `deployConfig.chains.${chainId}.inbox`);
  const cotiChainId = chainId === 1 ? COTI_MAINNET_CHAIN_ID : COTI_TESTNET_CHAIN_ID;
  const privateBudgetGuardCotiAddress = asAddress(
    requireEnv("PRIVATE_BUDGET_GUARD_COTI_ADDRESS"),
    "PRIVATE_BUDGET_GUARD_COTI_ADDRESS"
  );
  console.log(`[deploy-private-budget-guard] Inbox=${inboxAddress}`);
  console.log(
    `[deploy-private-budget-guard] PrivateBudgetGuardCoti=${privateBudgetGuardCotiAddress} cotiChainId=${cotiChainId}`
  );

  console.log("[deploy-private-budget-guard] Deploying PrivateBudgetGuard...");
  const privateBudgetGuard = await viem.deployContract("PrivateBudgetGuard", [inboxAddress], {
    client: { public: publicClient, wallet: walletClient },
  });
  console.log(
    `[deploy-private-budget-guard] PrivateBudgetGuard deployed: ${privateBudgetGuard.address}`
  );
  const fundTx = await walletClient.sendTransaction({ to: privateBudgetGuard.address, value: 10n ** 18n });
  await publicClient.waitForTransactionReceipt({ hash: fundTx });
  console.log("[deploy-private-budget-guard] Configuring PrivateBudgetGuard...");
  await privateBudgetGuard.write.configure(
    podConfigureKeepInbox(privateBudgetGuardCotiAddress, cotiChainId)
  );
  console.log("[deploy-private-budget-guard] PrivateBudgetGuard configured");

  console.log("[deploy-private-budget-guard] Writing deployment log entry");
  await appendDeploymentLog({
    contract: "PrivateBudgetGuard",
    address: privateBudgetGuard.address,
    chainId,
    network: networkLabel,
  });
  console.log("[deploy-private-budget-guard] Done");
};

main().catch((error) => {
  console.error("[deploy-private-budget-guard] Failed:", error);
  process.exitCode = 1;
});
