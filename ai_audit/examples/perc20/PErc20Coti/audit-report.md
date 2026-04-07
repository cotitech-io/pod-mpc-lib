# Audit report: `contracts/examples/perc20/PErc20Coti.sol`

**Solidity:** ^0.8.19  
**Purpose:** Example

## Introduction

COTI-side ledger for `PErc20` example; constructor mints to deployer hash.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| PEC-1 | **Privacy caveat** (NatSpec): decrypts recipient to plain address. | Medium |

## Conclusion

**Example only.**

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | |
| Inbox trust | Review | `onlyInbox` |
