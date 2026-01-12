import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import { network } from "hardhat";
import { RelayHelper } from "../scripts/test-helpers/relay-helper.js";

describe("Inbox", async function () {
  const { viem: viem1 } = await network.connect({ network: "chain1" });
  const publicClient1 = await viem1.getPublicClient();
  const [wallet1] = await viem1.getWalletClients();

  const { viem: viem2 } = await network.connect({ network: "chain2" });
  const publicClient2 = await viem2.getPublicClient();

  let inbox1: any;
  let inbox2: any;
  let relayHelper: RelayHelper;

  before(async function () {
    const chain1Id = 31337;
    const chain2Id = 31338;
    
    inbox1 = await viem1.deployContract("Inbox", [BigInt(chain1Id)]);
    inbox2 = await viem2.deployContract("Inbox", [BigInt(chain2Id)]);

    const privateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`;
    
    relayHelper = new RelayHelper(
      "http://127.0.0.1:8545",
      chain1Id,
      "http://127.0.0.1:8546",
      chain2Id,
      inbox1.address,
      inbox2.address,
      privateKey
    );
  });

  it("Should send a message from chain1 to chain2", async function () {
    const chain2Id = 31338;
    const reqId = 12345n;

    const deploymentBlock = await publicClient1.getBlockNumber();
    const tx = await inbox1.write.sendMessage([BigInt(chain2Id), reqId]);
    await publicClient1.waitForTransactionReceipt({ hash: tx });

    const events = await publicClient1.getContractEvents({
      address: inbox1.address,
      abi: inbox1.abi,
      eventName: "MessageSent",
      fromBlock: deploymentBlock,
      strict: true,
    });

    assert.equal(events.length, 1);
    assert.equal(Number(events[0].args.chainId), chain2Id);
    assert.equal(events[0].args.reqId, reqId);
    assert.equal(events[0].args.sender?.toLowerCase(), wallet1.account.address.toLowerCase());

    const messageHash = events[0].args.messageHash;
    assert.ok(messageHash);

    const message = await inbox1.read.getMessage([messageHash]);
    assert.equal(Number(message.chainId), chain2Id);
    assert.equal(message.reqId, reqId);
    assert.equal(message.sender.toLowerCase(), wallet1.account.address.toLowerCase());
    assert.equal(message.processed, false);
  });

  it("Should receive a message on chain2 after relaying", async function () {
    const chain1Id = 31337;
    const chain2Id = 31338;
    const reqId = 67890n;

    const deploymentBlock = await publicClient1.getBlockNumber();
    const tx = await inbox1.write.sendMessage([BigInt(chain2Id), reqId]);
    await publicClient1.waitForTransactionReceipt({ hash: tx });

    const events = await publicClient1.getContractEvents({
      address: inbox1.address,
      abi: inbox1.abi,
      eventName: "MessageSent",
      fromBlock: deploymentBlock,
      strict: true,
    });

    const messageEvent = events[events.length - 1];
    const messageHash = messageEvent.args.messageHash;
    const sender = messageEvent.args.sender;
    const timestamp = messageEvent.args.timestamp;

    assert.ok(messageHash && sender && timestamp);

    await relayHelper.relayMessage(
      chain1Id,
      Number(reqId),
      sender!,
      Number(timestamp!),
      messageHash!
    );

    const receivedMessage = await inbox2.read.getMessage([messageHash!]);
    assert.equal(Number(receivedMessage.chainId), chain1Id);
    assert.equal(receivedMessage.reqId, reqId);
    assert.equal(receivedMessage.sender.toLowerCase(), sender!.toLowerCase());
    assert.equal(receivedMessage.processed, true);

    const currentBlock = await publicClient2.getBlockNumber();
    const fromBlock = currentBlock > 10n ? currentBlock - 10n : 0n;
    const receivedEvents = await publicClient2.getContractEvents({
      address: inbox2.address,
      abi: inbox2.abi,
      eventName: "MessageReceived",
      fromBlock: fromBlock,
      strict: true,
    });

    const receivedEvent = receivedEvents.find((e) => e.args.messageHash === messageHash);
    assert.ok(receivedEvent);
    assert.equal(Number(receivedEvent!.args.chainId), chain1Id);
    assert.equal(receivedEvent!.args.reqId, reqId);
  });

  it("Should prevent sending message to the same chain", async function () {
    const inbox1ChainId = await inbox1.read.chainId();
    try {
      await inbox1.write.sendMessage([inbox1ChainId, 99999n]);
      assert.fail("Should have thrown an error");
    } catch (error: any) {
      const errorMsg = error.message || error.toString() || "";
      assert.ok(
        errorMsg.includes("cannot send to same chain") || 
        errorMsg.includes("Inbox: cannot send to same chain") ||
        errorMsg.includes("revert") ||
        error.cause?.message?.includes("cannot send to same chain"),
        `Should reject same chain. Got error: ${errorMsg}`
      );
    }
  });

  it("Should prevent receiving a message twice", async function () {
    const chain1Id = 31337;
    const chain2Id = 31338;
    const reqId = 11111n;

    const deploymentBlock = await publicClient1.getBlockNumber();
    const txHash = await inbox1.write.sendMessage([BigInt(chain2Id), reqId]);
    await publicClient1.waitForTransactionReceipt({ hash: txHash });

    const events = await publicClient1.getContractEvents({
      address: inbox1.address,
      abi: inbox1.abi,
      eventName: "MessageSent",
      fromBlock: deploymentBlock,
      strict: true,
    });

    const messageEvent = events[events.length - 1];
    const messageHash = messageEvent.args.messageHash;
    const sender = messageEvent.args.sender;
    const timestamp = messageEvent.args.timestamp;

    await relayHelper.relayMessage(
      chain1Id,
      Number(reqId),
      sender!,
      Number(timestamp!),
      messageHash!
    );

    try {
      await relayHelper.relayMessage(
        chain1Id,
        Number(reqId),
        sender!,
        Number(timestamp!),
        messageHash!
      );
      assert.fail("Should have thrown an error");
    } catch (error: any) {
      assert.ok(
        error.message.includes("already processed") || 
        error.message.includes("Message already processed"),
        "Should reject duplicate message"
      );
    }
  });

  it("Should track message count correctly", async function () {
    const chain2Id = 31338;
    const initialCount = await inbox1.read.getMessageCount();

    await inbox1.write.sendMessage([BigInt(chain2Id), 20000n]);
    await inbox1.write.sendMessage([BigInt(chain2Id), 20001n]);
    await inbox1.write.sendMessage([BigInt(chain2Id), 20002n]);

    const finalCount = await inbox1.read.getMessageCount();
    assert.equal(Number(finalCount), Number(initialCount) + 3);
  });
});
