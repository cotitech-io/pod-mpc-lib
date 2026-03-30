# Audit report: `contracts/InboxMiner.sol`

**Solidity:** ^0.8.19

## Introduction

Extends `InboxBase` and `MinerBase`: miners call `batchProcessRequests` to register and execute incoming requests. Owner configures oracle and fee configs; `collectFees` sends native balance to owner.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| IMi-1 | **`call{gas: targetFee}`**: If `targetFee` is wrong, execution fails or is under-gassed; errors recorded — **no classic reentrancy** from return data handling, but malicious target could consume gas deliberately. | Medium |
| IMi-2 | **Miner trust**: Malicious miner can reorder or censor batches — **liveness/fraud** at protocol level, not a Solidity bug. | High (system) |
| IMi-3 | **`collectFees`**: Push-style ETH to owner; if owner is a contract that reverts, fees lock until owner fixed — **consider pull pattern** for resilience. | Low |
| IMi-4 | **Nonce contiguity**: Strict nonce check — intentional; bad miner bricks batch. | Informational |

## Recommendations

- Monitor `FeeExecutionSettled` for gas anomalies.
- Document miner SLAs and dispute resolution off-chain.
- Consider **pull** fee withdrawal or try/catch pattern if owner must be a contract.

## Conclusion

**Critical path for cross-chain delivery.** Combines **privileged miners** and **untrusted execution targets**. Needs system audit + economic review.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | |
| Visibility | Pass | `onlyMiner` / `onlyOwner`. |
| Warnings | Review | CI. |
| Low-level `call` | **Review** | `call{gas: targetGasBudget}` — CEI: context cleared after subcall in success path; encode path clears early. |
| Reentrancy | Review | Target cannot reenter miner in same tx without being in same call stack — context zeroed before return in failure paths; verify ordering. |
| Short circuits | Review | Failed calls → `ErrorReceived`. |
| Dependencies | Pass | |
| Time | Pass | Timestamp on incoming request. |
| Rounding | Inherited | Fees from base. |
| Randomness | N/A | |
| Input validation | Pass | Source chain, addresses, nonce. |
| Unbounded loops | **Review** | `for (i < mined.length)` — miner-chosen length; OOG possible for huge batches. |
| Push payments | **Review** | `collectFees` push ETH. |
| Legacy | Pass | |
| `tx.origin` | Pass | |
| Version | Pass | |
| Tests | **Required** | Batch + fee + failure paths. |
| Resilience | Review | No pause. |
| Audits | **Required** | |
| High-risk: externals | **Yes** | `batchProcessRequests`, admin fns. |
| Assembly | Pass | None. |
| Admin | **Yes** | Owner fees + oracle config. |
| Value | **Yes** | `collectFees`. |
