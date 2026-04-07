# Audit report: `contracts/mpc/PodLib128.sol`

**Solidity:** ^0.8.19

## Introduction

Same as `PodLib64` for 128-bit `IPodExecutor128` operations.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| P128-1 | Same class as PodLib64 — **selector parity** and **encoding** correctness. | Medium |

## Recommendations

- Cross-reference with `MpcExecutor` 128-bit entrypoints.

## Conclusion

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| (Same structure as PodLib64) | Review | |
