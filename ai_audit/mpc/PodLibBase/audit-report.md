# Audit report: `contracts/mpc/PodLibBase.sol`

**Solidity:** ^0.8.19  
**Type:** Abstract mixin

## Introduction

Fee-aware `_sendTwoWayWithFee` / `_forwardTwoWay` and `onDefaultMpcError` callback surface. Depends on `inbox` and fee balances.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| PLB-1 | **`address(this).balance >= totalValueWei`**: User must attach value correctly; **race** if balance changes — typical pattern. | Low |
| PLB-2 | **Callback** `onDefaultMpcError` exposes `getOutboxError` — **reentrancy** if inbox ever called user code in error path — review inbox. | Low |

## Recommendations

- Document exact `msg.value` expectations for integrators.

## Conclusion

Thin wrapper; **inherits inbox security model**.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | |
| External calls | Review | `sendTwoWayMessage`, `getOutboxError`. |
| `tx.origin` | Pass | |
| Value | **Review** | `payable` send path. |
