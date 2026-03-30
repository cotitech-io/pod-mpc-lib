# Audit report: `contracts/mpc/coti-side/MpcExecutor.sol`

**Solidity:** ^0.8.19

## Introduction

Large `onlyInbox` facade over `MpcCore` for 64/128/256-bit ops; emits result events and uses `inbox.respond` for callbacks. **COTI precompile assumptions** — correctness of `MpcCore` is out of scope here but **trusted**.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| ME-1 | **Centralization**: Any compromise of `inbox` address (via `setInbox` in parent) bricks or hijacks executor — **constructor-only** `setInbox` in this contract — **Pass** if not upgradeable. | Medium |
| ME-2 | **Reentrancy**: `inbox.respond` after MPC work — if `inbox` reenters executor, **state** is minimal but **must** not assume reentrancy safety for future edits — **CEI**: MPC then respond. | Medium |
| ME-3 | **`mul*FromPlain`**: Requires `setPublic` + `mul` same contract — documented; proxy patterns must preserve. | Low |
| ME-4 | **Gas / OOG**: Large callbacks could fail — errors surface via inbox outbox. | Low |

## Recommendations

- Freeze `inbox` immutably if policy allows (no `setInbox` after deploy in `InboxUser` children — verify).
- Audit all paths that call `inbox.respond`.

## Conclusion

**High-value target** — large surface, depends on **inbox trust** and **MpcCore** correctness.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | 0.8 + MpcCore |
| Visibility | Pass | `external onlyInbox` |
| Low-level | Pass | No assembly in file |
| External calls | **High** | `inbox.respond` after MPC |
| Reentrancy | **Review** | Respond ordering |
| Dependencies | Review | COTI contracts |
| Time | N/A | |
| Rounding | N/A | |
| Input validation | Review | Trust `gt*` from inbox |
| Loops | N/A | |
| Push | N/A | |
| `tx.origin` | Pass | |
| Tests | **Required** | Per-op |
| Audits | **Required** | |
