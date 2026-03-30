# Audit report: `contracts/mpc/PodLib64.sol`

**Solidity:** ^0.8.19

## Introduction

Large set of internal helpers building `MpcMethodCall` for 64-bit `IPodExecutor64` operations and forwarding via `_forwardTwoWay`.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| P64-1 | **Code volume** — higher chance of copy-paste / selector mistakes; **review** against `IPodExecutor64`. | Medium |
| P64-2 | **Gas**: Many `internal` wrappers — acceptable; monitor bytecode size. | Informational |

## Recommendations

- Static check: selector hashes match `MpcExecutor` interface.

## Conclusion

**Mechanical encoding layer** — correctness depends on parity with executor.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | |
| Visibility | Pass | `internal` sends. |
| External calls | Pass | Via `PodLibBase` only. |
| Loops | N/A | Mostly none in hot paths. |
| Dependencies | Pass | `MpcAbiCodec`, `Inbox`. |
