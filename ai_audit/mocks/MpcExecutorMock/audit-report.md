# Audit report: `contracts/mocks/MpcExecutorMock.sol`

**Solidity:** ^0.8.19  
**Purpose:** Test double

## Introduction

Partial `MpcExecutor` mock: `add64`/`gt64`/`add128`/`add256` calling `inbox.respond`.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| MEM-1 | **Not a full executor** — behavior diverges from production `MpcExecutor`. | Informational |

## Conclusion

**Integration tests only.**

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Reentrancy | Review | `respond` in mock |
| `onlyInbox` | Pass | |
| Production | **N/A** | |
