# Audit report: `contracts/fee/uniswap/UniswapPriceOracle.sol`

**Solidity:** ^0.8.19

## Introduction

Extends `PriceOracle` to read Uniswap V2 reserves for local/remote token prices via `Math.mulDiv` (OZ). Spot price = `quote * PRICE_SCALE / base`.

## Vulnerabilities

| ID | Description | Severity |
|----|-------------|----------|
| UQ-1 | **Spot manipulation**: Single-block reserve manipulation can move price — **documented**; TWAP recommended for production. | High (economic) |
| UQ-2 | **Wrong token ordering**: `localTokenIsToken0` misconfiguration → inverted or nonsense prices — **deploy-time** risk. | High |
| UQ-3 | **Zero reserves**: Reverts `UniswapPriceOracleZeroReserves` — can **DoS `fetchPrices`** until liquidity returns. | Medium |
| UQ-4 | **`mulDiv`**: OZ audited — **Pass** for overflow-safe scaling. | Pass |

## Recommendations

- Deploy with **TWAP oracle** or off-chain verified feed for mainnet.
- Validate pair/token orientation in deployment scripts (on-chain read of `token0`/`token1`).

## Conclusion

**Suitable for dev/test or with external monitoring.** Not sufficient as sole security for high-value fee enforcement without TWAP/trusted feed.

---

## CryptoFin checklist — item by item

| Item | Status | Notes |
|------|--------|-------|
| Overflow | Pass | `Math.mulDiv`. |
| Low-level | Pass | `getReserves` external view. |
| External calls | **Review** | Pair contract trusted. |
| Reentrancy | Pass | View-only in `fetch*`. |
| Time | Review | Interval in parent uses `timestamp`. |
| Rounding | Review | Integer division in price. |
| Randomness | N/A | |
| Dependencies | Pass | OZ `Math`, V2 pair interface. |
| Manipulation | **High** | Spot reserves. |
