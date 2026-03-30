# Audit report: `contracts/fee/PriceOracle.sol`

**Solidity:** ^0.8.19

## Introduction

Ownable oracle with X128 cached prices, optional pull interval, `priceAdmin` manual overrides, and virtual `fetch*` hooks for subclasses.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| PO-1 | **Stale prices**: If `fetchPrices` is not called, cached values age — fee conversion uses **stale ratio** (documented tradeoff). | Medium (economic) |
| PO-2 | **`fetchBlockInterval`**: Storage present; **not enforced** in `_fetchIntervalsElapsed` in this base — **documentation / completeness** risk if users assume block gating. | Medium |
| PO-3 | **Admin trust**: Owner sets intervals and `priceAdmin`; malicious admin can manipulate fee acceptance. | Medium (centralization) |
| PO-4 | **Overflow**: 0.8.x safe; multiplication in fee manager uses oracle outputs — review there. | Pass |

## Recommendations

- Either **implement** `fetchBlockInterval` in `_fetchIntervalsElapsed` or remove/document as unused.
- Use timelock/multisig for owner and `priceAdmin`.
- TWAP or trusted feed for production (stated in `UniswapPriceOracle`).

## Conclusion

**Administrative and liveness assumptions** dominate. Sound for caching pattern if ops are trusted.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | 0.8.x |
| Visibility | Pass | |
| Warnings | Review | |
| Low-level | Pass | No `call` in base. |
| External calls | Pass | Virtual fetches in subclasses. |
| Dependencies | Pass | OZ `Ownable`. |
| Time | **Review** | `block.timestamp` for interval; miner skew ~seconds. |
| Rounding | N/A | Here |
| Randomness | N/A | |
| Inputs | Pass | |
| Loops | N/A | |
| Push | N/A | |
| Legacy | Pass | |
| `tx.origin` | Pass | |
| Version | Pass | |
| Tests | Review | |
| Resilience | Review | No circuit breaker on bad prices. |
| Audits | Informational | |
| High-risk | Review | Owner, `priceAdmin`. |
