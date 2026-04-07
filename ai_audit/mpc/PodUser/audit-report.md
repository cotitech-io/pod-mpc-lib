# Audit report: `contracts/mpc/PodUser.sol`

**Solidity:** ^0.8.19

## Introduction

Extends `InboxUser`: `mpcExecutorAddress`, `cotiChainId`, `configureCoti`, `ErrorRemoteCall` event.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| PU-1 | **`configureCoti` is `public virtual`** — unprotected by default; **children must restrict** who can reconfigure. | Medium (pattern) |

## Recommendations

- Override with `onlyOwner` or immutable config in production contracts.

## Conclusion

**Configuration footgun** if used naively.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | |
| Visibility | **Review** | `public configureCoti`. |
| Admin | **Review** | |
