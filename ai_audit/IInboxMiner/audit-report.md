# Audit report: `contracts/IInboxMiner.sol`

**Solidity:** ^0.8.19  
**Type:** Interface

## Introduction

Defines `MinedRequest` and miner-facing `batchProcessRequests` plus fee withdrawal `collectFees`. Concrete `InboxMiner` adds `onlyOwner` on `collectFees` (not expressible in the interface alone).

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| IM-1 | Interface cannot enforce who receives `collectFees`; mis-documentation could mislead integrators. | Informational |

## Recommendations

- Align NatSpec on implementations with actual access control (`onlyOwner` vs miner).

## Conclusion

**No runtime logic.** Security depends on `InboxMiner` + `MinerBase`.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow / SafeMath | N/A | |
| Visibility | Pass | |
| Warnings | N/A | |
| Problematic features | N/A | |
| External calls | N/A | |
| Dependencies | Pass | Imports `IInbox.sol`. |
| Time | N/A | |
| Rounding | N/A | |
| Randomness | N/A | |
| Input validation | N/A | Impl. |
| Unbounded loops | N/A | Impl. batches. |
| Push payments | N/A | |
| Legacy constructs | Pass | |
| `tx.origin` | N/A | |
| Version | Pass | |
| Tests | Review | Impl. |
| Unit / integration | Review | |
| Code freeze | Informational | |
| Resilience | N/A | |
| Audits | Informational | |
| High-risk: externals | Informational | `batchProcess` is critical path in impl. |
| Assembly | N/A | |
| Admin | Informational | `collectFees` in impl. |
| Timing | N/A | |
| Value | N/A | |
| Push | N/A | |
| Recent code | Review | |
