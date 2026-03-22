import assert from "node:assert/strict";
import { before, describe, it } from "node:test";
import { network } from "hardhat";
import { toFunctionSelector, zeroHash } from "viem";
import { decryptUint } from "@coti-io/coti-sdk-typescript";
import {
  buildEncryptedInput256,
  decryptUint256,
  getLatestRequest,
  getResponseRequestBySource,
  getTupleField,
  logStep,
  receiptWaitOptions,
} from "./mpc-test-utils.js";
import { mineRequest, setupContext256, type TestContext256 } from "./mpc-test-utils-256.js";

describe("MpcAdder256 (system)", async function () {
  const { viem: sepoliaViem } = await network.connect({ network: "hardhat" });
  const { viem: cotiViem } = await network.connect({ network: "cotiTestnet" });

  let ctx: TestContext256;

  before(async function () {
    process.env.COTI_REUSE_CONTRACTS = "true";
    ctx = await setupContext256({ sepoliaViem, cotiViem });
  });

  it("Should create an outgoing MPC add256 request from Sepolia", async function () {
    const a = 12n;
    const b = 30n;

    logStep("Test1: encrypt 256-bit inputs");
    const itA = await buildEncryptedInput256(ctx, a);
    const itB = await buildEncryptedInput256(ctx, b);
    logStep("Test1: sending add()");
    const txHash = await ctx.contracts.mpcAdderAsCoti.write.add([itA, itB]);
    logStep(`Test1: waiting for tx ${txHash}`);
    await ctx.sepolia.publicClient.waitForTransactionReceipt({
      hash: txHash,
      ...receiptWaitOptions,
    });
    logStep("Test1: tx confirmed, fetching latest request");
    const request = await getLatestRequest(ctx.contracts.inboxSepolia);

    // Selector for add256(gtUint256, gtUint256, address) on COTI (re-encoded from itUint256 on wire)
    const expectedSelector = toFunctionSelector(
      "add256(((uint256,uint256),(uint256,uint256)),((uint256,uint256),(uint256,uint256)),address)"
    );

    logStep("Test1: loaded request from hardhat inbox");
    assert.equal(Number(request.targetChainId), Number(ctx.chainIds.coti));
    assert.equal(
      request.targetContract.toLowerCase(),
      ctx.contracts.mpcExecutor.address.toLowerCase()
    );
    assert.equal(
      request.callerContract.toLowerCase(),
      ctx.contracts.mpcAdder.address.toLowerCase()
    );
    assert.equal(
      request.originalSender.toLowerCase(),
      ctx.contracts.mpcAdder.address.toLowerCase()
    );
    assert.equal(request.methodCall.selector, expectedSelector);
    assert.equal(request.isTwoWay, true);
    assert.equal(request.executed, false);
    assert.equal(request.sourceRequestId, zeroHash);
    assert.equal(
      request.callbackSelector,
      toFunctionSelector("receiveC(bytes)")
    );
    assert.equal(
      request.errorSelector,
      toFunctionSelector("onDefaultMpcError(bytes32)")
    );

    const { requestIdUsed: cotiRequestId } = await mineRequest(
      ctx,
      "coti",
      BigInt(ctx.chainIds.sepolia),
      request,
      "Test1"
    );
    const responseRequest = await getResponseRequestBySource(
      ctx.contracts.inboxCoti,
      cotiRequestId,
      "Test1"
    );
    await mineRequest(ctx, "sepolia", ctx.chainIds.coti, responseRequest, "Test1");
  });

  it("Should execute the MPC add256 request on COTI and create a response", async function () {
    const a = 7n;
    const b = 9n;

    logStep("Test2: encrypt 256-bit inputs");
    const itA = await buildEncryptedInput256(ctx, a);
    const itB = await buildEncryptedInput256(ctx, b);
    logStep("Test2: sending add()");
    const txHash = await ctx.contracts.mpcAdderAsCoti.write.add([itA, itB]);
    logStep(`Test2: waiting for tx ${txHash}`);
    await ctx.sepolia.publicClient.waitForTransactionReceipt({
      hash: txHash,
      ...receiptWaitOptions,
    });
    logStep("Test2: tx confirmed, loading latest request");
    const request = await getLatestRequest(ctx.contracts.inboxSepolia);
    const { requestIdUsed: cotiRequestId } = await mineRequest(
      ctx,
      "coti",
      BigInt(ctx.chainIds.sepolia),
      request,
      "Test2"
    );
    logStep("Test2: COTI processed, fetching response");

    let response: any;
    try {
      response = await ctx.contracts.inboxCoti.read.getInboxResponse([
        cotiRequestId,
      ]);
      logStep("Test2: loaded inbox response on COTI");
    } catch (error) {
      const inboxError = await ctx.contracts.inboxCoti.read.errors([
        cotiRequestId,
      ]);
      const errorCode = getTupleField(inboxError, "errorCode", 1);
      const errorMessage = getTupleField(inboxError, "errorMessage", 2);
      logStep(
        `Test2: no response, errorCode=${errorCode} errorMessage=${errorMessage}`
      );
      throw error;
    }
    assert.ok(response);

    const responseRequest = await getResponseRequestBySource(
      ctx.contracts.inboxCoti,
      cotiRequestId,
      "Test2"
    );

    const responseRequestId = getTupleField(responseRequest, "requestId", 0);
    assert.ok(responseRequestId);
    assert.equal(
      Number(responseRequest.targetChainId),
      ctx.chainIds.sepolia
    );
    assert.equal(
      responseRequest.targetContract.toLowerCase(),
      ctx.contracts.mpcAdder.address.toLowerCase()
    );
    assert.equal(responseRequest.isTwoWay, false);
    assert.equal(responseRequest.sourceRequestId, cotiRequestId);
    assert.equal(
      responseRequest.callbackSelector ?? "0x00000000",
      "0x00000000"
    );
    assert.equal(
      responseRequest.errorSelector ?? "0x00000000",
      toFunctionSelector("onDefaultMpcError(bytes32)")
    );
    assert.equal(responseRequest.methodCall.selector, "0x00000000");
    const receiveCSelector = toFunctionSelector("receiveC(bytes)");
    const responseDataHex = responseRequest.methodCall.data as `0x${string}`;
    assert.ok(responseDataHex.startsWith(receiveCSelector));

    logStep("Test2: applying response on hardhat inbox");
    await mineRequest(ctx, "sepolia", ctx.chainIds.coti, responseRequest, "Test2");
    logStep("Test2: response applied on hardhat");
  });

  it("Should decrypt the MPC add256 result on Sepolia", async function () {
    const a = 15n;
    const b = 27n;

    logStep("Test3: encrypt 256-bit inputs");
    const itA = await buildEncryptedInput256(ctx, a);
    const itB = await buildEncryptedInput256(ctx, b);
    logStep("Test3: sending add()");
    const txHash = await ctx.contracts.mpcAdderAsCoti.write.add([itA, itB]);
    logStep(`Test3: waiting for tx ${txHash}`);
    await ctx.sepolia.publicClient.waitForTransactionReceipt({
      hash: txHash,
      ...receiptWaitOptions,
    });
    logStep("Test3: tx confirmed, loading latest request");
    const request = await getLatestRequest(ctx.contracts.inboxSepolia);
    const { requestIdUsed: cotiRequestId } = await mineRequest(
      ctx,
      "coti",
      BigInt(ctx.chainIds.sepolia),
      request,
      "Test3"
    );
    logStep("Test3: COTI processed, applying response on hardhat");

    const responseRequest = await getResponseRequestBySource(
      ctx.contracts.inboxCoti,
      cotiRequestId,
      "Test3"
    );

    logStep("Test3: applying response on hardhat inbox");
    await mineRequest(ctx, "sepolia", ctx.chainIds.coti, responseRequest, "Test3");
    logStep("Test3: response applied, decrypting result");

    const encryptedResult = await ctx.contracts.mpcAdder.read.resultCiphertext();
    const decrypted = decryptUint256(encryptedResult, ctx.crypto.userKey, decryptUint);
    assert.equal(decrypted, a + b);
  });

  it("Should handle large 256-bit values", async function () {
    // Test with values that actually use more than 64 bits
    const a = (1n << 65n) + 100n; // Value larger than 64 bits
    const b = (1n << 65n) + 200n;

    logStep("Test4: encrypt large 256-bit inputs");
    const itA = await buildEncryptedInput256(ctx, a);
    const itB = await buildEncryptedInput256(ctx, b);
    logStep("Test4: sending add()");
    const txHash = await ctx.contracts.mpcAdderAsCoti.write.add([itA, itB]);
    logStep(`Test4: waiting for tx ${txHash}`);
    await ctx.sepolia.publicClient.waitForTransactionReceipt({
      hash: txHash,
      ...receiptWaitOptions,
    });
    logStep("Test4: tx confirmed, loading latest request");
    const request = await getLatestRequest(ctx.contracts.inboxSepolia);
    const { requestIdUsed: cotiRequestId } = await mineRequest(
      ctx,
      "coti",
      BigInt(ctx.chainIds.sepolia),
      request,
      "Test4"
    );
    logStep("Test4: COTI processed, applying response on hardhat");

    const responseRequest = await getResponseRequestBySource(
      ctx.contracts.inboxCoti,
      cotiRequestId,
      "Test4"
    );

    logStep("Test4: applying response on hardhat inbox");
    await mineRequest(ctx, "sepolia", ctx.chainIds.coti, responseRequest, "Test4");
    logStep("Test4: response applied, decrypting result");

    const encryptedResult = await ctx.contracts.mpcAdder.read.resultCiphertext();
    const decrypted = decryptUint256(encryptedResult, ctx.crypto.userKey, decryptUint);
    assert.equal(decrypted, a + b);
  });
});
