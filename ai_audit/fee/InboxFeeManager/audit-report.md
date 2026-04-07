# Audit report: `contracts/fee/InboxFeeManager.sol`

**Solidity:** ^0.8.19  
**Type:** Abstract mixin

## Introduction

Converts `msg.value` to gas units via `tx.gasprice` (or `DEFAULT_GAS_PRICE`), validates minima against templates, maps remote budgets using oracle **price ratio** (`localP * remoteGas / remoteP` style via `validateRemoteFee`).

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| FM-1 | **`tx.gasprice == 0`**: Uses `DEFAULT_GAS_PRICE` — **meta-tx or unusual networks** could behave differently than expected; document. | Low |
| FM-2 | **Truncation**: Integer division in wei→gas and oracle ratio — **rounds down**; could edge-case reject borderline fees. | Low |
| FM-3 | **Oracle manipulation** (Uniswap spot): If prices manipulated, remote min fee check changes — **economic** risk. | Medium (when Uniswap used) |
| FM-4 | **`calculateTwoWayFeeRequired`**: Heuristic / UI helper; **complex formula** — verify against product expectations; not used for on-chain enforcement of sends. | Informational |

## Recommendations

- Add fuzz tests for fee boundaries and oracle zero/very large values.
- Document rounding direction for integrators.

## Conclusion

**Business-logic heavy.** Primary risks are **economic** (oracle, gas price choice) not reentrancy.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | 0.8; watch mul order in ratio. |
| Visibility | Pass | `internal` / `external view` helper. |
| Low-level | Pass | |
| External calls | Review | Reads `priceOracle.get*`. |
| Reentrancy | Pass | `view` paths for validation; no state change in view. |
| Dependencies | Pass | `PriceOracle` interface. |
| Time | N/A | Block time not used here. |
| Rounding | **Review** | Division truncation. |
| Input validation | Review | Template validation in `_updateMinFeeConfigs`. |
| Loops | N/A | |
| Push | N/A | |
| `tx.origin` | Pass | Uses `tx.gasprice` only. |
| Tests | **Required** | Fee edge cases. |
