# Audit report: `contracts/mpc/coti-side/IPodExecutorOps.sol`

**Solidity:** ^0.8.19  
**Type:** Interface group (`IPodExecutor64` / `128` / `256`)

## Introduction

Declares MPC executor entrypoints consumed by `MpcExecutor` and referenced by `PodLib*`. Imports `MpcCore` for types.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| IPO-1 | **Plaintext random** methods documented as returning `abi.encode(uint256)` — implementers must match or PoD decoders break. | Informational |

## Recommendations

- Keep ABI synchronized with `MpcExecutor` deployment.

## Conclusion

**Specification only.**

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | N/A | |
| Visibility | Pass | `external` |
| Low-level | N/A | |
| External calls | N/A | |
| Dependencies | Pass | COTI `MpcCore` types |
| All other core | N/A | |
| Tests | N/A | Impl. |
| Resilience | N/A | |
| High-risk | Informational | Large external surface in impl. |
