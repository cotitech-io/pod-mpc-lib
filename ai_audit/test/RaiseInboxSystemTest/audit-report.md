# Audit report: `contracts/test/RaiseInboxSystemTest.sol`

**Solidity:** ^0.8.19  
**Purpose:** System test contracts

## Introduction

Two contracts: `RaiseInboxTestCoti` forwards `triggerRaise` to `inbox.raise`; `RaiseInboxTestSepolia` initiates two-way flows and implements `onRaiseError`.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| RIT-1 | **Test contracts** — minimal validation; arbitrary payloads to `raise`. | Informational |

## Conclusion

**Deploy only to testnets** with known counterparties.

---

## CryptoFin checklist — item by item

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Overflow | Pass | |
| 2 | SafeMath | N/A | |
| 3 | Visibility | Pass | |
| 4 | Warnings | Review | |
| 5 | `send` | Pass | |
| 6 | Low-level | Pass | |
| 7 | `var` | Pass | |
| 8 | Reentrancy | Review | `inbox.raise` |
| 9 | Short circuits | Low | |
| 10 | ERC20 | N/A | |
| 11 | Call stack | Informational | |
| 12 | Dependencies | Pass | `IInbox`, `InboxUser` |
| 13 | Minimize code | N/A | Test |
| 14 | Time | N/A | |
| 15 | Rounding | N/A | |
| 16 | Randomness | N/A | |
| 17 | Input validation | Fail for prod | `triggerRaise` arbitrary bytes |
| 18 | Loops | N/A | |
| 19 | Push | N/A | |
| 20 | Legacy | Pass | |
| 21 | `tx.origin` | Pass | |
| 22 | Version | Pass | |
| 23 | Coverage | Informational | Covered by `inbox-raise` test |
| 24–26 | Tests / freeze | Informational | |
| 27–32 | Resilience / audits | N/A | Test |
| 33 | External/public | Review | `triggerRaise` |
| 34 | Assembly | Pass | |
| 35 | Admin | N/A | |
| 36 | Timing | N/A | |
| 37 | Value | Review | `receive()` payable on Sepolia side |
| 38 | Push | N/A | |
| 39 | Recent code | Review | |
