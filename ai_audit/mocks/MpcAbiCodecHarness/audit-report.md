# Audit report: `contracts/mocks/MpcAbiCodecHarness.sol`

**Solidity:** ^0.8.19  
**Purpose:** Test harness

## Introduction

Exposes `MpcAbiCodec` build/reencode paths for Hardhat tests.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| MH-1 | Unrestricted external wrappers — **test only**. | Informational |

## Conclusion

**Do not deploy to production** as security boundary.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Access control | **Fail** for prod | Open externals |
| Dependencies | Pass | `MpcAbiCodec`, `MpcCore` |
