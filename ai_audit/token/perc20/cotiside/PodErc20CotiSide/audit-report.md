# Audit report: `contracts/token/perc20/cotiside/PodErc20CotiSide.sol`

**Solidity:** ^0.8.19

## Introduction

Ownable + `InboxUser`: authorizes remote `PodERC20`. Stores `ctUint256` balances/allowances; MPC ops via `MpcCore`; `respond`/`raise` to PoD.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| PCS-1 | **Owner**: `setAuthorizedRemote` — **critical**; compromised owner redirects funds. | High |
| PCS-2 | **Inbox-only** ops assume inbox is correct — **trust inbox**. | Medium |
| PCS-3 | **Plaintext address derivation** in some flows (documented in examples) — **privacy** not fully on-chain. | Medium |
| PCS-4 | **MPC errors**: `MpcCore` failures — must not leave inconsistent state — **review** revert vs raise paths. | Medium |

## Recommendations

- Multisig owner; timelock on `setAuthorizedRemote`.
- Audit all `respond`/`raise` payloads for strict ABI conformance.

## Conclusion

**Production-critical** with **strong admin and inbox assumptions**.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | |
| Visibility | Pass | `onlyOwner` / inbox gates |
| Low-level | Pass | |
| External calls | **High** | `inbox.respond`/`raise` |
| Reentrancy | **Review** | After MPC |
| Dependencies | `MpcCore`, OZ `Ownable` |
| Time | N/A | |
| Rounding | Review | MPC |
| Admin | **High** | Owner |
| Value | Review | Native fee on inbox sends |
