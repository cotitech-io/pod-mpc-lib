import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import { network } from "hardhat";
import { decodeAbiParameters, encodeFunctionData, toFunctionSelector, zeroHash } from "viem";

describe("Adder", async function () {
  const { viem: viem1 } = await network.connect({ network: "chain1" });
  const publicClient1 = await viem1.getPublicClient();
  const [wallet1] = await viem1.getWalletClients();

  const { viem: viem2 } = await network.connect({ network: "chain2" });
  const publicClient2 = await viem2.getPublicClient();
  const [wallet2] = await viem2.getWalletClients();

  let inbox1: any;
  let inbox2: any;
  let adder: any;
  let mpcExecutor: any;

  const getTupleField = (value: any, key: string, index: number) =>
    value?.[key] ?? value?.[index];

  before(async function () {
    const chain1Id = 31337;
    const chain2Id = 31338;

    inbox1 = await viem1.deployContract("Inbox", [BigInt(chain1Id)]);
    inbox2 = await viem2.deployContract("Inbox", [BigInt(chain2Id)]);

    adder = await viem1.deployContract("Adder", [inbox1.address]);
    mpcExecutor = await viem2.deployContract("MpcExecutorMock", [inbox2.address]);

    await adder.write.configureCoti([mpcExecutor.address, BigInt(chain2Id)]);
    await inbox2.write.addMiner([wallet2.account.address]);
  });

  it("Should create an outgoing request from the source contract", async function () {
    const chain1Id = 31337;
    const chain2Id = 31338;
    const a = 12n;
    const b = 30n;

    const fromBlock = await publicClient1.getBlockNumber();
    const txHash = await adder.write.add([a, b, wallet1.account.address]);
    await publicClient1.waitForTransactionReceipt({ hash: txHash });

    const events = (await publicClient1.getContractEvents({
      address: inbox1.address,
      abi: inbox1.abi,
      eventName: "MessageSent",
      fromBlock,
      strict: true,
    })) as any[];

    assert.ok(events.length > 0);
    const messageEvent = events[events.length - 1];
    const requestId = messageEvent.args.requestId!;

    const expectedData = encodeFunctionData({
      abi: [
        {
          type: "function",
          name: "add",
          stateMutability: "nonpayable",
          inputs: [
            { name: "a", type: "uint256" },
            { name: "b", type: "uint256" },
            { name: "cOwner", type: "address" },
          ],
          outputs: [],
        },
      ],
      functionName: "add",
      args: [a, b, wallet1.account.address],
    });
    const expectedSelector = expectedData.slice(0, 10);
    const expectedArgsData = `0x${expectedData.slice(10)}`;

    const request = await inbox1.read.requests([requestId]);
    const targetChainId = getTupleField(request, "targetChainId", 1);
    const targetContract = getTupleField(request, "targetContract", 2);
    const callerContract = getTupleField(request, "callerContract", 4);
    const originalSender = getTupleField(request, "originalSender", 5);
    const requestMethodCall = getTupleField(request, "methodCall", 3);
    const requestSelector = getTupleField(requestMethodCall, "selector", 0);
    const requestData = getTupleField(requestMethodCall, "data", 1);
    const isTwoWay = getTupleField(request, "isTwoWay", 9);
    const executed = getTupleField(request, "executed", 10);
    const sourceRequestId = getTupleField(request, "sourceRequestId", 11);

    assert.equal(Number(targetChainId), chain2Id);
    assert.equal(targetContract.toLowerCase(), mpcExecutor.address.toLowerCase());
    assert.equal(callerContract.toLowerCase(), adder.address.toLowerCase());
    assert.equal(originalSender.toLowerCase(), adder.address.toLowerCase());
    assert.equal(requestSelector, expectedSelector);
    assert.equal(requestData, expectedArgsData);
    assert.equal(isTwoWay, true);
    assert.equal(executed, false);
    assert.equal(sourceRequestId, zeroHash);

    assert.equal(Number(messageEvent.args.targetChainId), chain2Id);
    assert.equal(messageEvent.args.targetContract?.toLowerCase(), mpcExecutor.address.toLowerCase());
    const eventMethodCall = messageEvent.args.methodCall;
    assert.equal(eventMethodCall.selector, expectedSelector);
    assert.equal(eventMethodCall.data, expectedArgsData);
    assert.equal(messageEvent.args.callbackSelector, toFunctionSelector("receiveC(bytes)"));
    assert.equal(messageEvent.args.errorSelector, toFunctionSelector("onDefaultMpcError(bytes32)"));

    const [unpackedChainId, nonce] = await inbox1.read.unpackRequestId([requestId]);
    assert.equal(Number(unpackedChainId), chain1Id);
    assert.ok(Number(nonce) > 0);
  });

  it("Should execute an incoming request and deliver to target", async function () {
    const chain1Id = 31337;
    const chain2Id = 31338;
    const a = 7n;
    const b = 9n;

    const fromBlock = await publicClient1.getBlockNumber();
    const txHash = await adder.write.add([a, b, wallet1.account.address]);
    await publicClient1.waitForTransactionReceipt({ hash: txHash });

    const events = (await publicClient1.getContractEvents({
      address: inbox1.address,
      abi: inbox1.abi,
      eventName: "MessageSent",
      fromBlock,
      strict: true,
    })) as any[];

    const messageEvent = events[events.length - 1];
    const requestId = messageEvent.args.requestId!;
    const request = await inbox1.read.requests([requestId]);
    const methodCall =
      getTupleField(request, "methodCall", 3) ??
      messageEvent.args.methodCall;
    const callbackSelector =
      getTupleField(request, "callbackSelector", 7) ??
      messageEvent.args.callbackSelector ??
      "0x00000000";
    const errorSelector =
      getTupleField(request, "errorSelector", 8) ??
      messageEvent.args.errorSelector ??
      "0x00000000";
    assert.ok(methodCall);

    const execFromBlock = await publicClient2.getBlockNumber();
    await inbox2.write.batchProcessRequests([
      BigInt(chain1Id),
      [
        {
          requestId,
          sourceContract: adder.address,
          targetContract: mpcExecutor.address,
          methodCall,
          callbackSelector,
          errorSelector,
          isTwoWay: true,
          sourceRequestId: zeroHash,
        },
      ],
    ]);

    const incoming = await inbox2.read.incomingRequests([requestId]);
    const incomingTargetChainId = getTupleField(incoming, "targetChainId", 1);
    const incomingExecuted = getTupleField(incoming, "executed", 10);
    assert.equal(incomingExecuted, true);
    assert.equal(Number(incomingTargetChainId), chain1Id);

    const addEvents = (await publicClient2.getContractEvents({
      address: mpcExecutor.address,
      abi: mpcExecutor.abi,
      eventName: "AddResult",
      fromBlock: execFromBlock,
      strict: true,
    })) as any[];
    const addEvent = addEvents.find(
      (event) => event.args.cOwner?.toLowerCase() === wallet1.account.address.toLowerCase()
    );
    assert.ok(addEvent);
    assert.equal(addEvent!.args.c, a + b);

    const response = await inbox2.read.getInboxResponse([requestId]);
    const [decoded] = decodeAbiParameters([{ type: "uint256" }], response);
    assert.equal(decoded, a + b);
  });

  it("Should create a response request and apply it back on chain1", async function () {
    const chain1Id = 31337;
    const chain2Id = 31338;
    const a = 15n;
    const b = 27n;

    const fromBlock = await publicClient1.getBlockNumber();
    const txHash = await adder.write.add([a, b, wallet1.account.address]);
    await publicClient1.waitForTransactionReceipt({ hash: txHash });

    const events = (await publicClient1.getContractEvents({
      address: inbox1.address,
      abi: inbox1.abi,
      eventName: "MessageSent",
      fromBlock,
      strict: true,
    })) as any[];

    const messageEvent = events[events.length - 1];
    const requestId = messageEvent.args.requestId!;
    const request = await inbox1.read.requests([requestId]);
    const methodCall =
      getTupleField(request, "methodCall", 3) ??
      messageEvent.args.methodCall;
    const callbackSelector =
      getTupleField(request, "callbackSelector", 7) ??
      messageEvent.args.callbackSelector ??
      "0x00000000";
    const errorSelector =
      getTupleField(request, "errorSelector", 8) ??
      messageEvent.args.errorSelector ??
      "0x00000000";
    assert.ok(methodCall);

    await inbox2.write.batchProcessRequests([
      BigInt(chain1Id),
      [
        {
          requestId,
          sourceContract: adder.address,
          targetContract: mpcExecutor.address,
          methodCall,
          callbackSelector,
          errorSelector,
          isTwoWay: true,
          sourceRequestId: zeroHash,
        },
      ],
    ]);

    const responseCount = await inbox2.read.getRequestsLen();
    assert.ok(Number(responseCount) > 0);
    const responseRequests = await inbox2.read.getRequests([0, responseCount]);

    const responseRequest = (responseRequests as any[]).find(
      (req) => getTupleField(req, "sourceRequestId", 11) === requestId
    );
    assert.ok(responseRequest);

    const responseRequestId = getTupleField(responseRequest, "requestId", 0);
    const responseTargetChainId = getTupleField(responseRequest, "targetChainId", 1);
    const responseTargetContract = getTupleField(responseRequest, "targetContract", 2);
    const responseMethodCall = getTupleField(responseRequest, "methodCall", 3);
    const responseSelector = getTupleField(responseMethodCall, "selector", 0);
    const responseData = getTupleField(responseMethodCall, "data", 1);
    const responseSourceContract = getTupleField(responseRequest, "originalSender", 5);
    const responseCallbackSelector = getTupleField(responseRequest, "callbackSelector", 7) ?? "0x00000000";
    const responseErrorSelector = getTupleField(responseRequest, "errorSelector", 8) ?? "0x00000000";
    const responseIsTwoWay = getTupleField(responseRequest, "isTwoWay", 9);
    const responseSourceRequestId = getTupleField(responseRequest, "sourceRequestId", 11);

    assert.ok(responseRequestId);
    assert.ok(responseTargetContract);
    assert.ok(responseSourceContract);
    assert.ok(responseData);
    assert.ok(responseSelector);

    assert.equal(Number(responseTargetChainId), chain1Id);
    assert.equal(responseTargetContract.toLowerCase(), adder.address.toLowerCase());
    assert.equal(responseIsTwoWay, false);
    assert.equal(responseSourceRequestId, requestId);

    const responsePayload = await inbox2.read.getInboxResponse([requestId]);
    const receiveCData = encodeFunctionData({
      abi: [
        {
          type: "function",
          name: "receiveC",
          stateMutability: "nonpayable",
          inputs: [{ name: "data", type: "bytes" }],
          outputs: [],
        },
      ],
      functionName: "receiveC",
      args: [responsePayload],
    });
    const applyMethodCall = {
      selector: "0x00000000",
      data: receiveCData,
      datatypes: [],
      datalens: [],
    };

    await inbox1.write.batchProcessRequests([
      BigInt(chain2Id),
      [
        {
          requestId: responseRequestId,
          sourceContract: responseSourceContract,
          targetContract: responseTargetContract,
          methodCall: applyMethodCall,
          callbackSelector: responseCallbackSelector,
          errorSelector: responseErrorSelector,
          isTwoWay: false,
          sourceRequestId: responseSourceRequestId,
        },
      ],
    ]);

    const adderResult = await adder.read.result();
    assert.equal(adderResult, a + b);
  });
});
