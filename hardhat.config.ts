import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  // Configure the default hardhat network
  // Chain ID can be overridden via HARDHAT_CHAIN_ID environment variable
  networks: {
    hardhat: {
      type: "edr-simulated",
      chainId: parseInt(process.env.HARDHAT_CHAIN_ID || "31337"),
    },
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
    // Chain 1 for multichain message passing testing
    // Note: The actual chain ID is set in the contract constructor
    // This network config just needs to match what the node reports
    chain1: {
      type: "http",
      url: "http://127.0.0.1:8545",
      chainId: 31337, // Node reports this, but contract uses its own chainId
      accounts: {
        mnemonic: "test test test test test test test test test test test junk",
      },
    },
    // Chain 2 for multichain message passing testing
    // Note: The actual chain ID is set in the contract constructor
    // This network config just needs to match what the node reports
    chain2: {
      type: "http",
      url: "http://127.0.0.1:8546",
      chainId: 31337, // Node reports this, but contract uses its own chainId
      accounts: {
        mnemonic: "test test test test test test test test test test test junk",
      },
    },
  },
});
