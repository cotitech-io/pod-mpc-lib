import path from "node:path";
import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { defineConfig } from "hardhat/config";
export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: { version: "0.8.26", path: path.resolve("node_modules/solc/soljson.js") },
  networks: { hardhat: { type: "edr-simulated", chainId: 31338 } },
});
