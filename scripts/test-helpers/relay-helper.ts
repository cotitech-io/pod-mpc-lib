import { createPublicClient, createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { hardhat } from "viem/chains";
import { RelayNode } from "../relay-node.js";

const INBOX_ABI = [
  {
    type: "event",
    name: "MessageSent",
    inputs: [
      { name: "messageHash", type: "bytes32", indexed: true },
      { name: "chainId", type: "uint256", indexed: true },
      { name: "reqId", type: "uint256", indexed: true },
      { name: "sender", type: "address", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "function",
    name: "receiveMessage",
    stateMutability: "nonpayable",
    inputs: [
      { name: "sourceChainId", type: "uint256" },
      { name: "reqId", type: "uint256" },
      { name: "sender", type: "address" },
      { name: "timestamp", type: "uint256" },
      { name: "messageHash", type: "bytes32" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "getMessage",
    stateMutability: "view",
    inputs: [{ name: "messageHash", type: "bytes32" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "chainId", type: "uint256" },
          { name: "reqId", type: "uint256" },
          { name: "sender", type: "address" },
          { name: "timestamp", type: "uint256" },
          { name: "processed", type: "bool" },
        ],
      },
    ],
  },
] as const;

export class RelayHelper {
  private chain1Client: ReturnType<typeof createPublicClient>;
  private chain2Client: ReturnType<typeof createPublicClient>;
  private chain2Wallet: ReturnType<typeof createWalletClient>;
  private inbox1Address: `0x${string}`;
  private inbox2Address: `0x${string}`;
  private chain1Url: string;
  private chain1Id: number;
  private chain2Url: string;
  private chain2Id: number;
  private privateKey: `0x${string}`;

  constructor(
    chain1Url: string,
    chain1Id: number,
    chain2Url: string,
    chain2Id: number,
    inbox1Address: `0x${string}`,
    inbox2Address: `0x${string}`,
    privateKey: `0x${string}`
  ) {
    this.chain1Url = chain1Url;
    this.chain1Id = chain1Id;
    this.chain2Url = chain2Url;
    this.chain2Id = chain2Id;
    this.privateKey = privateKey;
    const account = privateKeyToAccount(privateKey);
    const nodeChainId = 31337;

    this.chain1Client = createPublicClient({
      chain: { ...hardhat, id: chain1Id },
      transport: http(chain1Url),
    });

    this.chain2Client = createPublicClient({
      chain: { ...hardhat, id: nodeChainId },
      transport: http(chain2Url),
    });

    this.chain2Wallet = createWalletClient({
      account,
      chain: { ...hardhat, id: nodeChainId },
      transport: http(chain2Url),
    });

    this.inbox1Address = inbox1Address;
    this.inbox2Address = inbox2Address;
  }

  async getMessagesFromChain1(fromBlock: bigint = 0n, toBlock: bigint | "latest" = "latest"): Promise<any[]> {
    const logs = await this.chain1Client.getLogs({
      address: this.inbox1Address,
      event: {
        type: "event",
        name: "MessageSent",
        inputs: [
          { type: "bytes32", indexed: true, name: "messageHash" },
          { type: "uint256", indexed: true, name: "chainId" },
          { type: "uint256", indexed: true, name: "reqId" },
          { type: "address", indexed: false, name: "sender" },
          { type: "uint256", indexed: false, name: "timestamp" },
        ],
      },
      fromBlock,
      toBlock: toBlock === "latest" ? await this.chain1Client.getBlockNumber() : (toBlock as bigint),
    });

    return logs.map((log) => ({
      messageHash: log.args.messageHash,
      chainId: log.args.chainId ? Number(log.args.chainId) : 0,
      reqId: log.args.reqId ? Number(log.args.reqId) : 0,
      sender: log.args.sender,
      timestamp: log.args.timestamp ? Number(log.args.timestamp) : 0,
      blockNumber: log.blockNumber,
    }));
  }

  async relayMessage(
    sourceChainId: number,
    reqId: number,
    sender: `0x${string}`,
    timestamp: number,
    messageHash: `0x${string}`
  ): Promise<`0x${string}`> {
    const message = await this.chain2Client.readContract({
      address: this.inbox2Address,
      abi: INBOX_ABI,
      functionName: "getMessage",
      args: [messageHash],
    });

    if (message.processed) {
      throw new Error("Message already processed");
    }

    const hash = await this.chain2Wallet.writeContract({
      address: this.inbox2Address,
      abi: INBOX_ABI,
      functionName: "receiveMessage",
      args: [BigInt(sourceChainId), BigInt(reqId), sender, BigInt(timestamp), messageHash],
    });

    await this.chain2Client.waitForTransactionReceipt({ hash });
    return hash;
  }

  async relayAllPendingMessages(fromBlock: bigint = 0n): Promise<number> {
    const messages = await this.getMessagesFromChain1(fromBlock);
    let relayed = 0;

    for (const msg of messages) {
      if (msg.messageHash && msg.sender) {
        try {
          await this.relayMessage(
            msg.chainId,
            msg.reqId,
            msg.sender as `0x${string}`,
            msg.timestamp,
            msg.messageHash as `0x${string}`
          );
          relayed++;
        } catch (error: any) {
          if (error.message !== "Message already processed") {
            throw error;
          }
        }
      }
    }

    return relayed;
  }

  createRelayNode(pollInterval: number = 2000): RelayNode {
    return new RelayNode({
      chain1Url: this.chain1Url,
      chain1Id: this.chain1Id,
      chain2Url: this.chain2Url,
      chain2Id: this.chain2Id,
      inbox1Address: this.inbox1Address,
      inbox2Address: this.inbox2Address,
      privateKey: this.privateKey,
      pollInterval,
    });
  }
}
