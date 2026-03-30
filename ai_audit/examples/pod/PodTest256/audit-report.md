# Audit report: `contracts/examples/pod/PodTest256.sol`

**Solidity:** ^0.8.19  
**Purpose:** Test harness

## Introduction

Same pattern as `PodTest64` for 256-bit `PodLib` operations.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| PT256-1 | Open test surface — **not production**. | Informational |

## Conclusion

**Test only.**

---

## CryptoFin checklist — item by item

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Overflow / underflow | Pass | 0.8.x |
| 2 | SafeMath (legacy) | N/A | |
| 3 | Function visibility | Review | Many externals |
| 4 | Compiler warnings | Review | |
| 5 | `send` | Pass | |
| 6 | Low-level calls | Pass | |
| 7 | `var` | Pass | |
| 8 | Reentrancy | Low | `onlyInbox` |
| 9 | Short circuits | Low | |
| 10 | ERC20 freezing | N/A | |
| 11 | Call stack depth | Informational | |
| 12 | Dependencies | Pass | |
| 13 | Minimize code | N/A | Harness |
| 14 | Time manipulation | N/A | |
| 15 | Rounding | N/A | |
| 16 | Randomness | N/A | |
| 17 | Input validation | Fail for prod | No access control |
| 18 | Unbounded loops | N/A | |
| 19 | Push payments | N/A | |
| 20 | Legacy constructs | Pass | |
| 21 | `tx.origin` | Pass | |
| 22 | Version upgrade | Review | |
| 23 | Coverage | Informational | |
| 24 | Unit tests | N/A | |
| 25 | Integration | N/A | |
| 26 | Code freeze | Informational | |
| 27 | Failure modes | N/A | |
| 28 | Asserts | N/A | |
| 29 | Speed bumps | N/A | |
| 30 | Circuit breakers | N/A | |
| 31 | External audits | N/A | |
| 32 | Post-audit time | N/A | |
| 33 | External/public | High | Test |
| 34 | Assembly | Pass | |
| 35 | Superuser | N/A | |
| 36 | Timing | N/A | |
| 37 | Value / payable | Review | |
| 38 | Push payments | N/A | |
| 39 | Recent code | Review | |
