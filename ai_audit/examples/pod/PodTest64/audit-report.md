# Audit report: `contracts/examples/pod/PodTest64.sol`

**Solidity:** ^0.8.19  
**Purpose:** Test harness

## Introduction

Exercises 64-bit `PodLib` operations; stores `lastResult` / `lastRequestId`.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| PT64-1 | Open externals — **test fixture only**. | Informational |

## Conclusion

**Not for production.**

---

## CryptoFin checklist — item by item

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Overflow / underflow | Pass | 0.8.x |
| 2 | SafeMath (legacy) | N/A | Use built-in checks |
| 3 | Function visibility | Review | Many `external` test entrypoints |
| 4 | Compiler warnings | Review | CI |
| 5 | `send` misuse | Pass | Not used |
| 6 | Low-level calls (`call`/delegatecall/asm) | Pass | None |
| 7 | `var` | Pass | Not used |
| 8 | Reentrancy on external calls | Low | `onlyInbox` receive path |
| 9 | Short-circuit / DoS | Low | Test contract |
| 10 | ERC20 freezing | N/A | |
| 11 | Call stack depth | Informational | Rare |
| 12 | Audited dependencies | Pass | COTI + local |
| 13 | Minimize custom code | N/A | Test harness |
| 14 | Timestamp manipulation | N/A | |
| 15 | Rounding errors | N/A | |
| 16 | Weak randomness | N/A | |
| 17 | Input validation | Fail for prod | No auth |
| 18 | Unbounded loops | N/A | |
| 19 | Push payments | N/A | |
| 20 | Legacy constructs | Pass | `keccak256` |
| 21 | `tx.origin` | Pass | Not used |
| 22 | Solidity version upgrade | Review | Track 0.8 |
| 23 | Test coverage | Informational | Harness itself |
| 24 | Unit tests | N/A | |
| 25 | Integration tests | N/A | |
| 26 | Code freeze | Informational | |
| 27 | Disaster failure modes | N/A | |
| 28 | Critical asserts | N/A | |
| 29 | Speed bumps | N/A | |
| 30 | Circuit breakers | N/A | |
| 31 | External audits | N/A | Test |
| 32 | Post-audit buffer | N/A | |
| 33 | External/public surface | High exposure | Intended for tests |
| 34 | Assembly | Pass | |
| 35 | Superuser | N/A | |
| 36 | Timing / congestion | N/A | |
| 37 | Value / payable | Review | Example `payable` paths |
| 38 | Push vs pull | N/A | |
| 39 | Recently written code | Review | |
