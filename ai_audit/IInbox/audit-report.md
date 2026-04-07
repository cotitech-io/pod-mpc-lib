# Audit report: `contracts/IInbox.sol`

**Solidity:** ^0.8.19  
**Type:** Interface (no runtime bytecode)

## Introduction

`IInbox` defines the cross-chain messaging API: outbound sends, inbound execution helpers (`respond` / `raise`), queries, and request-ID packing. Implementations inherit fee logic (`InboxFeeManager`) and miner delivery (`InboxMiner`). **No executable code** — findings are specification-level (ABI guarantees, misleading doc risks).

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| I-1 | Struct field semantics (`targetFee` / `callerFee` as gas units) rely entirely on implementers; interface cannot enforce. | Informational |
| I-2 | `MpcMethodCall` raw mode (`selector == 0`) shifts encoding burden to callers — misuse can brick or mis-route calls in implementations. | Low (implementation) |

## Recommendations

- Keep NatSpec aligned with `InboxBase` / `InboxFeeManager` so integrators do not confuse wei vs gas units.
- Consider EIP-165 or a version byte on the inbox if multiple incompatible implementations may exist.

## Conclusion

The interface is **minimal attack surface** (none at deploy time). Risk migrates entirely to **concrete implementations** (`InboxBase`, `InboxMiner`).

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow / SafeMath | N/A | No code; 0.8 semantics apply to implementers. |
| Function visibility | Pass | Interface functions correctly `external`. |
| Compiler warnings | N/A | Interface only. |
| `send` / low-level `call` / `var` | N/A | None. |
| External calls / reentrancy | N/A | No calls. |
| Dependencies | Pass | Only Solidity types. |
| Time manipulation | N/A | No time. |
| Rounding | N/A | No math. |
| Randomness | N/A | |
| Input validation | Informational | Documented on impl.; not enforceable here. |
| Unbounded loops | N/A | |
| Push payments | N/A | |
| Legacy constructs | Pass | `keccak256` not used in interface. |
| `tx.origin` | N/A | |
| Solidity version | Pass | ^0.8.19 |
| Test coverage | Review | N/A for interface; need impl. tests. |
| Unit / integration tests | Review | Via `InboxBase` tests. |
| Code freeze | Informational | Process. |
| Failure / invariants | N/A | |
| Speed bumps / circuit breakers | N/A | Spec-level only. |
| External audits | Informational | Whole system. |
| Post-audit time | Informational | Process. |
| **High-risk areas** | | |
| External/public surface | Pass | Intentionally large API; impl. must harden. |
| Assembly / low-level | N/A | |
| Superuser | N/A | |
| Timing / congestion | N/A | |
| Value / payable | Informational | `payable` on sends — fee logic in impl. |
| Push payments | N/A | |
| Recent code | Review | Track impl. churn. |
