import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { defineConfig } from "hardhat/config";
export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: { profiles: { default: { version: "0.8.28" } } },
  networks: { hardhat: { type: "edr-simulated", chainId: 31337 } },
});
