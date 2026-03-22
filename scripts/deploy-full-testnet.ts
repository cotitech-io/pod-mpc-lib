import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { network } from "hardhat";
import {
  appendDeploymentLog,
  asAddress,
  getChainConfig,
  getViemClients,
  readDeployConfig,
  requireEnv,
} from "./deploy-utils.js";

const SOURCE_NETWORK = "sepolia";
const COTI_NETWORK = "cotiTestnet";
const ONLY_MPC_ADDER = process.env.ONLY_MPC_ADDER === "true";
const deployConfigPath = path.resolve(process.cwd(), "deployConfig.json");

const runHardhat = (args: string[]) =>
  new Promise<void>((resolve, reject) => {
    const child = spawn("npx", ["hardhat", ...args], { stdio: "inherit" });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`Hardhat command failed: ${args.join(" ")}`));
      }
    });
  });

const verifyContract = async (
  networkName: string,
  contract: string,
  address: `0x${string}`,
  constructorArgs: string[]
) => {
  console.log(`[deploy-full-testnet] Verifying ${contract} on ${networkName}...`);
  try {
    await runHardhat(["verify", "--network", networkName, address, ...constructorArgs]);
    console.log(`[deploy-full-testnet] Verified ${contract} on ${networkName}`);
  } catch (error) {
    console.warn(
      `[deploy-full-testnet] Verification failed for ${contract} on ${networkName}:`,
      error
    );
  }
};

const main = async () => {
  const minerAddress = asAddress(requireEnv("MINER_ADDRESS"), "MINER_ADDRESS");
  console.log(`[deploy-full-testnet] Using miner: ${minerAddress}`);

  console.log(`[deploy-full-testnet] Connecting to source network ${SOURCE_NETWORK}`);
  const sourceConnection = await network.connect({ network: SOURCE_NETWORK });
  const { viem: sourceViem, provider: sourceProvider, networkName: sourceNetworkLabel } =
    sourceConnection;
  const {
    chainId: sourceChainId,
    chainName: sourceChainLabel,
    publicClient: sourcePublicClient,
    walletClient: sourceWalletClient,
  } = await getViemClients(sourceViem, sourceProvider, sourceNetworkLabel);
  console.log(
    `[deploy-full-testnet] Source connected: chainId=${sourceChainId} network=${sourceChainLabel}`
  );

  console.log(`[deploy-full-testnet] Connecting to COTI network ${COTI_NETWORK}`);
  const cotiConnection = await network.connect({ network: COTI_NETWORK });
  const { viem: cotiViem, provider: cotiProvider, networkName: cotiNetworkLabel } =
    cotiConnection;
  const {
    chainId: cotiChainIdNumber,
    chainName: cotiChainLabel,
    publicClient: cotiPublicClient,
    walletClient: cotiWalletClient,
  } = await getViemClients(cotiViem, cotiProvider, cotiNetworkLabel);
  const cotiChainId = BigInt(cotiChainIdNumber);
  console.log(
    `[deploy-full-testnet] COTI connected: chainId=${cotiChainIdNumber} network=${cotiChainLabel}`
  );

  console.log("[deploy-full-testnet] Deploying source Inbox...");
  const sourceInbox = await sourceViem.deployContract("Inbox", [0n], {
    client: { public: sourcePublicClient, wallet: sourceWalletClient },
  });
  console.log(`[deploy-full-testnet] Source Inbox deployed: ${sourceInbox.address}`);
  console.log("[deploy-full-testnet] Adding source miner...");
  await sourceInbox.write.addMiner([minerAddress]);
  console.log("[deploy-full-testnet] Source miner added");
  await appendDeploymentLog({
    contract: "Inbox",
    address: sourceInbox.address,
    chainId: sourceChainId,
    network: sourceChainLabel,
  });

  console.log("[deploy-full-testnet] Deploying COTI Inbox...");
  const cotiInbox = await cotiViem.deployContract("Inbox", [0n], {
    client: { public: cotiPublicClient, wallet: cotiWalletClient },
  });
  console.log(`[deploy-full-testnet] COTI Inbox deployed: ${cotiInbox.address}`);
  console.log("[deploy-full-testnet] Deploying MpcExecutor...");
  const cotiExecutor = await cotiViem.deployContract("MpcExecutor", [cotiInbox.address], {
    client: { public: cotiPublicClient, wallet: cotiWalletClient },
  });
  console.log(`[deploy-full-testnet] MpcExecutor deployed: ${cotiExecutor.address}`);
  console.log("[deploy-full-testnet] Adding COTI miner...");
  await cotiInbox.write.addMiner([minerAddress]);
  console.log("[deploy-full-testnet] COTI miner added");
  await appendDeploymentLog({
    contract: "Inbox",
    address: cotiInbox.address,
    chainId: cotiChainIdNumber,
    network: cotiChainLabel,
  });
  await appendDeploymentLog({
    contract: "MpcExecutor",
    address: cotiExecutor.address,
    chainId: cotiChainIdNumber,
    network: cotiChainLabel,
  });

  let millionaireAddress: `0x${string}` | undefined;
  if (!ONLY_MPC_ADDER) {
    console.log("[deploy-full-testnet] Deploying Millionaire...");
    const millionaire = await sourceViem.deployContract("Millionaire", [sourceInbox.address], {
      client: { public: sourcePublicClient, wallet: sourceWalletClient },
    });
    millionaireAddress = millionaire.address;
    console.log(`[deploy-full-testnet] Millionaire deployed: ${millionaire.address}`);
    console.log("[deploy-full-testnet] Configuring Millionaire...");
    await millionaire.write.configureCoti([cotiExecutor.address, cotiChainId]);
    console.log("[deploy-full-testnet] Millionaire configured");
    await appendDeploymentLog({
      contract: "Millionaire",
      address: millionaire.address,
      chainId: sourceChainId,
      network: sourceChainLabel,
    });
  }

  console.log("[deploy-full-testnet] Deploying MpcAdder...");
  const mpcAdder = await sourceViem.deployContract("MpcAdder", [sourceInbox.address], {
    client: { public: sourcePublicClient, wallet: sourceWalletClient },
  });
  console.log(`[deploy-full-testnet] MpcAdder deployed: ${mpcAdder.address}`);
  console.log("[deploy-full-testnet] Configuring MpcAdder...");
  await mpcAdder.write.configureCoti([cotiExecutor.address, cotiChainId]);
  console.log("[deploy-full-testnet] MpcAdder configured");
  await appendDeploymentLog({
    contract: "MpcAdder",
    address: mpcAdder.address,
    chainId: sourceChainId,
    network: sourceChainLabel,
  });

  let pErc20Address: `0x${string}` | undefined;
  if (!ONLY_MPC_ADDER) {
    console.log("[deploy-full-testnet] Deploying PErc20...");
    const pErc20 = await sourceViem.deployContract("PErc20", [sourceInbox.address], {
      client: { public: sourcePublicClient, wallet: sourceWalletClient },
    });
    pErc20Address = pErc20.address;
    console.log(`[deploy-full-testnet] PErc20 deployed: ${pErc20.address}`);
    console.log("[deploy-full-testnet] Configuring PErc20...");
    await pErc20.write.configureCoti([cotiExecutor.address, cotiChainId]);
    console.log("[deploy-full-testnet] PErc20 configured");
    await appendDeploymentLog({
      contract: "PErc20",
      address: pErc20.address,
      chainId: sourceChainId,
      network: sourceChainLabel,
    });
  }

  console.log("[deploy-full-testnet] Deploying PErc20Coti...");
  const pErc20Coti = await cotiViem.deployContract("PErc20Coti", [cotiInbox.address], {
    client: { public: cotiPublicClient, wallet: cotiWalletClient },
  });
  console.log(`[deploy-full-testnet] PErc20Coti deployed: ${pErc20Coti.address}`);
  await appendDeploymentLog({
    contract: "PErc20Coti",
    address: pErc20Coti.address,
    chainId: cotiChainIdNumber,
    network: cotiChainLabel,
  });

  const deployConfig = await readDeployConfig();
  const sourceChainConfig = getChainConfig(deployConfig, sourceChainId, "source");
  sourceChainConfig.inbox = sourceInbox.address;
  const cotiChainConfig = getChainConfig(deployConfig, cotiChainIdNumber, "coti");
  cotiChainConfig.inbox = cotiInbox.address;
  cotiChainConfig.cotiExecutor = cotiExecutor.address;
  await fs.writeFile(deployConfigPath, `${JSON.stringify(deployConfig, null, 2)}\n`, "utf8");
  console.log("[deploy-full-testnet] Updated deployConfig.json");

  await verifyContract(SOURCE_NETWORK, "Inbox", sourceInbox.address, ["0"]);
  await verifyContract(COTI_NETWORK, "Inbox", cotiInbox.address, ["0"]);
  await verifyContract(COTI_NETWORK, "MpcExecutor", cotiExecutor.address, [cotiInbox.address]);
  if (millionaireAddress) {
    await verifyContract(SOURCE_NETWORK, "Millionaire", millionaireAddress, [sourceInbox.address]);
  }
  await verifyContract(SOURCE_NETWORK, "MpcAdder", mpcAdder.address, [sourceInbox.address]);
  if (pErc20Address) {
    await verifyContract(SOURCE_NETWORK, "PErc20", pErc20Address, [sourceInbox.address]);
  }
  await verifyContract(COTI_NETWORK, "PErc20Coti", pErc20Coti.address, [cotiInbox.address]);

  console.log("[deploy-full-testnet] Done");
};

main().catch((error) => {
  console.error("[deploy-full-testnet] Failed:", error);
  process.exitCode = 1;
});
