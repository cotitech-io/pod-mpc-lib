# Audit report: `contracts/InboxUser.sol`

**Solidity:** ^0.8.19  
**Type:** Abstract mixin

## Introduction

Provides `inbox` reference, `OnlyInbox` error, `onlyInbox` modifier, and internal `setInbox`. Used by POD and COTI-side contracts.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| IU-1 | If `setInbox` is callable more than once in a child without guard, inbox could be swapped by compromised admin — **depends on child**. | Low (pattern) |
| IU-2 | `onlyInbox` compares `msg.sender` to `address(inbox)` — correct; no `tx.origin`. | Pass |

## Recommendations

- Children should document whether `setInbox` is single-shot (constructor-only) or upgradeable.

## Conclusion

**Small, auditable surface.** Core access control is sound for the stated model.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | No arithmetic. |
| Visibility | Pass | `internal` / `external` via modifier. |
| Warnings | Pass | |
| Low-level calls | Pass | None. |
| Reentrancy | Pass | No external calls in modifier. |
| Dependencies | Pass | `IInbox`. |
| Time | N/A | |
| Rounding | N/A | |
| Randomness | N/A | |
| Input validation | Review | `_inbox` not validated non-zero here — child may add. |
| Loops | N/A | |
| Push payments | N/A | |
| Legacy | Pass | |
| `tx.origin` | Pass | Not used. |
| Version | Pass | |
| Tests | Review | Via consumers. |
| Resilience | Informational | No pause. |
| Audits | Informational | |
| High-risk: externals | Pass | `on*` in children use `onlyInbox`. |
| Assembly | Pass | None. |
| Admin | Review | `setInbox` in children. |
