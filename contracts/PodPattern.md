# PoD Pattern

## How to write privacy dApps (p.dApp):

A privacy dApp for example, runs on Etherum (client network). And runs asynchronous privacy method
calls which in turn they run on the Coti network.

To make a privacy method call on the client network:

1. Client side: BuildA a request:
```
IInbox.MpcMethodCall memory methodCall =
            MpcAbiCodec.create(IPrivateContract.privateMethod.selector, 3)
            .addArgument(a) // For gt data type, we use it equivalent, which is user encrypted
            .addArgument(b)
            .addArgument(cOwner)
            .build();
```
2. Client side: Send the one-way or two-way request
```
        return IInbox(inbox).sendTwoWayMessage(
            cotiChainId,
            mpcExecutorAddress,
            methodCall,
            callbackSelector,
            errorSelector
        );
```
3. Client side: Handle callback (bytes data is passed and need to abi.decode accordingly)

Now on the Coti side:
4. Implement IPrivateContract.privateMethod.selector, unless method is already implemented as
commonly supported privacy methods in MpcExecutor.sol

## Handling privacy data types

On the client side, we have only two privacy data types. (See https://github.com/coti-io/coti-contracts/blob/main/contracts/utils/mpc/MpcCore.sol)

1. User encrypted data. E.g. itUint64
2. Offboarded to user data. E.g. ctUint64