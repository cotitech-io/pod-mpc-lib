# CryptoFin Solidity Auditing Checklist (reference copy)

Source: [cryptofinlabs/audit-checklist — README.md](https://github.com/cryptofinlabs/audit-checklist/blob/master/README.md) (original targets Solidity v0.4.24; interpret for modern 0.8.x).

## Core checks

- Prevent overflow and underflow; SafeMath (legacy) / 0.8 checked math
- Function visibility — correct `external` / `public` / `internal` / `private`
- Fix compiler warnings
- Avoid problematic features — `send`, low-level `call`/`delegatecall`/`callcode`, `var`
- External calls — reentrancy (checks-effects-interactions), short circuits / DoS, ERC20 edge cases, call stack depth
- Dependencies — audited deps, minimize custom code
- Time manipulation — `block.timestamp` sensitivity
- Rounding errors — truncation impact
- Randomness — no weak on-chain randomness for security
- Validate inputs — `require` / custom errors on externals
- Unbounded loops
- Push vs pull payments
- Deprecated constructs — `selfdestruct`, `sha3` vs `keccak256`
- Do not use `tx.origin` for auth
- Verify compiler version upgrade notes

## Testing and software engineering

- Test coverage (e.g. branch coverage goals)
- Unit tests — edge cases
- Integration tests
- Code freeze before mainnet

## Resilience

- Worst failure modes
- Invariants / asserts where appropriate
- Speed bumps / delays
- Circuit breakers / pause

## Auditing process

- External audits (prefer multiple sequential reviewers)
- Time to fix post-audit

## High-risk areas (extra scrutiny)

- External and public functions
- Assembly and low-level calls
- Superuser / admin roles
- Timing and congestion
- Value transfer and `payable`
- Push payments
- Recently changed code

## Security resources (external)

- [Ethereum Security Guide](https://github.com/ethereum/wiki/wiki/Safety)
- [Consensys Smart Contract Best Practices](https://consensys.github.io/smart-contract-best-practices/)
- [DASP Top 10](https://dasp.co/)
