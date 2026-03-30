# Audit report: `contracts/MinerBase.sol`

**Solidity:** ^0.8.19

## Introduction

Ownable registry of miner addresses. `onlyMiner` gates miner-only inbox functions. `addMiner` / `removeMiner` are `onlyOwner`.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| MB-1 | Compromised owner can add malicious miners → arbitrary `batchProcessRequests` execution on `InboxMiner`. | Medium (ops / centralization) |
| MB-2 | No event indexing requirement — monitoring relies on off-chain indexing of `MinerAdded`/`MinerRemoved`. | Informational |

## Recommendations

- Use multisig / timelock for owner.
- Consider upper bound on miner count if gas DoS on owner operations is a concern (usually not).

## Conclusion

**Standard Ownable pattern.** Operational security dominates technical risk.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | Mapping bool; 0.8.x. |
| Visibility | Pass | |
| Warnings | Pass | |
| Low-level | Pass | None. |
| External calls | Pass | OpenZeppelin `Ownable`. |
| Dependencies | Review | OZ v5 — use audited release. |
| Time | N/A | |
| Rounding | N/A | |
| Randomness | N/A | |
| Input validation | Pass | `miner != 0`, duplicate checks. |
| Loops | N/A | |
| Push payments | N/A | |
| Legacy | Pass | |
| `tx.origin` | Pass | |
| Version | Pass | |
| Tests | Review | |
| Resilience | Informational | No circuit breaker. |
| Audits | Informational | |
| High-risk: admin | **Review** | Owner is superuser for miners. |
