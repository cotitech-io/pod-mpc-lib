# Audit report: `contracts/token/perc20/IPodERC20.sol`

**Solidity:** ^0.8.19  
**Type:** Interface + events

## Introduction

Async private ERC-20 surface: ciphertext balances/allowances, events, `TransferRequested`/`ApprovalRequested` structs.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| IE-1 | **Specification risk** — implementers must enforce callback ordering and nonces; not enforceable at interface. | Informational |

## Conclusion

**No bytecode.** See `PodERC20`.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| All | N/A / Inherited | See implementation. |
