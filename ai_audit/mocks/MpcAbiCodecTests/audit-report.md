# Audit report: `contracts/mocks/MpcAbiCodecTests.sol`

**Solidity:** ^0.8.19  
**Purpose:** Test contract

## Introduction

Stores last arguments from codec test callbacks for assertion in TS tests.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| MAT-1 | Anyone can clobber storage — **test only**. | Informational |

## Conclusion

**Test only.**

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Access control | **Fail** for prod | Public setters |
| External calls | Pass | Minimal |
