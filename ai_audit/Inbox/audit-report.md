# Audit report: `contracts/Inbox.sol`

**Solidity:** ^0.8.19  
**Type:** Thin production contract

## Introduction

`Inbox` inherits `InboxMiner` and wires `MinerBase` owner to `msg.sender` at deploy. No additional state or logic.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| IN-1 | Deployer becomes both miner-registry owner and initial context — operational centralization. | Informational |

## Recommendations

- Document operational procedures for `Ownable` transfer and miner registration post-deploy.

## Conclusion

**Attack surface equals `InboxMiner`.** No independent bugs expected from this file.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | Inherited; 0.8.x. |
| Visibility | Pass | Default constructor visibility. |
| Warnings | Pass | None specific to file. |
| Low-level features | Inherited | See `InboxMiner`. |
| External calls | Inherited | |
| Dependencies | Pass | Local inherits only. |
| Time | Inherited | |
| Rounding | Inherited | |
| Randomness | N/A | |
| Input validation | Inherited | |
| Loops | Inherited | |
| Push payments | Inherited | `collectFees`. |
| Legacy | Pass | |
| `tx.origin` | Pass | Not used. |
| Version | Pass | |
| Test coverage | Review | Covered via inbox system tests. |
| Unit / integration | Review | |
| Code freeze | Informational | |
| Failure modes | Inherited | |
| Circuit breakers | None | Inherited none. |
| Audits | Informational | System-level. |
| High-risk areas | Inherited | Miner + inbox paths. |
