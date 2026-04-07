# Audit report: `contracts/examples/perc20/PErc20.sol`

**Solidity:** ^0.8.19  
**Purpose:** Example

## Introduction

Minimal PoD 64-bit balance example; two-way inbox to `IPErc20Coti`.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| PE20-1 | **Explicitly not production** (NatSpec): no allowances, weak pending-state. | High if misused |

## Conclusion

**Do not deploy as production token.**

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| All | Review | Example risk |
