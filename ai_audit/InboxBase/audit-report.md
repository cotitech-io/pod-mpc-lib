# Audit report: `contracts/InboxBase.sol`

**Solidity:** ^0.8.19  
**Role:** Core inbox + fee mixin + MPC calldata encoding

## Introduction

`InboxBase` stores requests/responses/errors, enforces fee templates via `InboxFeeManager`, emits events, and executes `_encodeMethodCall` with optional `try/catch` via external self-call. Inbound execution uses `call{gas: targetFee}` in `InboxMiner`. Trust assumptions: miners deliver ordered payloads; MPC codec correctness; target contracts behave.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| IB-1 | **Reentrancy (target contract)**: During `respond` / `raise`, `_sendOneWayMessage` can trigger further cross-chain work; state updates use checks before external calls in many paths, but **target contracts** invoked from miner path can reenter if they call back into inbox — mitigated by context checks; still review **third-party** targets. | Medium |
| IB-2 | **`_encodeMethodCallExternal`**: `external` for try/catch; gated by `msg.sender == address(this)` — **Pass** if no delegatecall proxy mis-set. | Low |
| IB-3 | **Gas / unbounded `getRequests`**: `len` can be large → OOG in view call — **DoS of read RPC**, not funds. | Low |
| IB-4 | **`require` strings**: Centralization of revert reasons; no sensitive data. | Informational |
| IB-5 | **Same-chain send blocked**: `targetChainId != chainId` — intentional. | Pass |

## Recommendations

- Document **checks-effects-interactions** for any future change that adds external calls before state finalization in `respond`/`raise`.
- Cap or document max `len` for `getRequests` off-chain.
- Formal review of `MpcAbiCodec.reEncodeWithGt` integration.

## Conclusion

**High-complexity contract.** Primary risks: **integration with untrusted targets**, **miner ordering assumptions**, and **codec correctness**. Requires professional audit + integration tests.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow / underflow | Pass | Solidity 0.8; fee math in mixin. |
| SafeMath analog | Pass | Built-in checks. |
| Visibility | Review | `_encodeMethodCallExternal` is `external` — intentional; self-only. |
| Compiler warnings | Review | Fix any in CI. |
| `send` | Pass | Not used. |
| Low-level `call` | **Review** | `InboxMiner` uses `call{gas}`; CEI in miner path. |
| `var` | Pass | Not used. |
| Reentrancy | **Review** | Target reentrancy during execution; `respond`/`raise` ordering. |
| Short circuits / DoS | Review | Failed target calls recorded; miner liveness separate. |
| ERC20 quirks | N/A | Not ERC20 here. |
| Call stack depth | Low | Historical; EVM changes; test deep calls if concerned. |
| Dependencies | Review | OZ not in base; `MpcAbiCodec`, `InboxFeeManager`. |
| Libraries | Pass | Codec library. |
| Time manipulation | Review | `block.timestamp` on requests — ordering only; not security-critical for consensus. |
| Rounding | Review | Fee conversion in `InboxFeeManager` (wei→gas, oracle ratio). |
| Randomness | N/A | |
| Input validation | Pass | `require` on chain/target; fee reverts. |
| Unbounded loops | Review | `getRequests` loop over `len`; miner batch loop in `InboxMiner`. |
| Push payments | N/A | Withdraw in miner. |
| Legacy constructs | Pass | `keccak256`. |
| `tx.origin` | Pass | Not used. |
| Solidity upgrade | Review | Track 0.8.x patch notes. |
| Test coverage | **Gap** | Aim high branch coverage; not 100% claimed. |
| Unit tests | Review | |
| Integration tests | **Required** | Cross-chain flows. |
| Code freeze | Informational | Process. |
| Disaster failure modes | Review | Miner censorship, wrong chain config. |
| Invariants / assert | Review | No global supply invariant; request maps. |
| Speed bumps | None | |
| Circuit breakers | None | Consider pause for prod. |
| External audits | **Required** | Multiple reviewers. |
| Post-audit time | Informational | |
| **High-risk areas** | | |
| External/public | **High** | Sends, queries, encode external. |
| Assembly | Pass | None in file (check `MpcAbiCodec`). |
| Superuser | N/A | Owner hooks in miner. |
| Timing / congestion | Review | Gas price 0 uses default in fees. |
| Value / payable | **High** | `sendTwoWay`/`sendOneWay` hold fees. |
| Push payments | Review | `collectFees` pull to owner. |
| Recent code | Review | Track diffs pre-mainnet. |
