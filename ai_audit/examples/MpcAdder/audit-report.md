# Audit report: `contracts/examples/MpcAdder.sol`

**Solidity:** ^0.8.19  
**Purpose:** Example

## Introduction

Demonstrates `PodLib` 64-bit `add` with inbox wiring.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| EX-1 | **Example code** — not audited for production. | Informational |

## Conclusion

**Sample only.**

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | |
| Visibility | Pass | |
| Value | Review | `payable` add |
| Production | **N/A** | Example |
