# Audit report: `contracts/token/perc20/PodERC20.sol`

**Solidity:** ^0.8.19  
**Role:** PoD-side private token

## Introduction

Implements `IPodERC20` + `InboxUser`: async cross-chain transfers/approvals/burns/syncs; callbacks `onlyInbox` with peer check (`cotiChainId`, `cotiSideContract`). **Documented** weak spot: `setPublicAmountsEnabled` is **unrestricted** (NatSpec warns).

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| PE-1 | **`setPublicAmountsEnabled`**: Anyone can toggle — **breaks privacy expectations** if used in prod as-is. | **High** |
| PE-2 | **Reentrancy**: Callbacks may interact with external code paths — ensure **checks-effects-interactions** for any future ETH transfers here (minimal today). | Medium |
| PE-3 | **Nonce / ordering**: Stale COTI callbacks must not overwrite — logic relies on `balanceNonces` — **review** for off-by-one. | Medium |
| PE-4 | **Pending locks**: `_pendingTransferRequestIds` — **liveness** if stuck states. | Low |
| PE-5 | **Unbounded `syncBalances` accounts** — OOG in COTI callback or PoD send. | Low |

## Recommendations

- **Gate `setPublicAmountsEnabled`** with `onlyOwner` or remove for mainnet.
- Full professional audit on callback decoding and balance update paths.
- Fuzz nonce edge cases.

## Conclusion

**High-complexity financial contract.** **Must** address public toggle and undergo external audit before mainnet.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | 0.8.x |
| Visibility | **Review** | `setPublicAmountsEnabled` external unprotected |
| Low-level | Pass | |
| External calls | **High** | Inbox sends; callback trust |
| Reentrancy | **Review** | Callbacks |
| Dependencies | Review | OZ N/A; `MpcAbiCodec`, `Inbox` |
| Time | Review | Timestamp in requests |
| Rounding | Review | MPC / decrypt |
| Input validation | **Review** | Peer checks on callbacks |
| Loops | Review | `syncBalances` arrays |
| Push payments | N/A | |
| `tx.origin` | Pass | |
| Tests | **Required** | Full coverage |
| Circuit breaker | None | Consider pause |
| High-risk | **Yes** | Callbacks, value, async |
