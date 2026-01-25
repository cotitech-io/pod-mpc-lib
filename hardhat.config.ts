import "dotenv/config";
import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";

const envOrConfig = (key: string) => process.env[key] ?? configVariable(key);
const privateKeyFor = (key: string) =>
  process.env[key] ?? process.env.PRIVATE_KEY ?? configVariable(key);

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          evmVersion: "paris",
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      production: {
        version: "0.8.28",
        settings: {
          evmVersion: "paris",
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
      accounts: process.env.PRIVATE_KEY
        ? [
            {
              privateKey: process.env.PRIVATE_KEY,
              balance: "100000000000000000000",
            },
          ]
        : undefined,
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
      url: envOrConfig("SEPOLIA_RPC_URL"),
      accounts: [privateKeyFor("SEPOLIA_PRIVATE_KEY")],
    },
    cotiTestnet: {
      type: "http",
      chainType: "l1",
      url: envOrConfig("COTI_TESTNET_RPC_URL"),
      accounts: [privateKeyFor("COTI_TESTNET_PRIVATE_KEY")],
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
