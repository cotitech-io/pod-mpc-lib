# Audit report: `contracts/mpccodec/MpcAbiCodec.sol`

**Solidity:** ^0.8.19  
**Type:** Library

## Introduction

Builds `MpcMethodCall` contexts, re-encodes it-* types to gt-* for dispatch, and validates ciphertexts where applicable. **High complexity** — central to calldata correctness for MPC inbox flows.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| MAC-1 | **Parsing / bounds**: Slicing and cursor arithmetic — must be **fuzzed**; any off-by-one could corrupt calldata or leak memory. | High (if bug exists) |
| MAC-2 | **Gas**: Large dynamic args → **OOG** — availability, not theft. | Low |
| MAC-3 | **Assumptions on `datatypes`/`datalens`**: Malformed user input could cause revert or wrong encoding — mitigated by inbox + tests. | Medium |

## Recommendations

- Dedicated audit + **formal** or exhaustive fuzzing on `reEncodeWithGt` and `build`.
- Differential testing against reference encoder.

## Conclusion

**Critical dependency.** Treat as top-priority for external review.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Review | Prefer explicit checks in hot loops; 0.8 default. |
| Visibility | Pass | `library` internal fns. |
| Low-level | Review | Heavy `bytes` manipulation. |
| External calls | Pass | None in library core. |
| Dependencies | Pass | `IInbox`, `MpcCore`. |
| Rounding | Review | Tail offsets. |
| Unbounded loops | Review | Arg count loops. |
| Tests | **Required** | Property + fuzz. |
