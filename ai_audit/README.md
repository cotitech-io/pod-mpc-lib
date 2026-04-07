# AI-assisted audit reports

This directory contains **one folder per Solidity contract** under `contracts/`, each with an `audit-report.md`.

## Methodology

Reports follow a fixed structure:

1. **Introduction** — Purpose, trust boundaries, and dependencies.
2. **Vulnerabilities** — Findings with **severity** (Critical / High / Medium / Low / Informational).
3. **Recommendations** — Actionable mitigations mapped to findings.
4. **Conclusion** — Residual risk and deployment notes.
5. **CryptoFin checklist** — Every item from [CryptoFin’s Solidity Auditing Checklist](https://github.com/cryptofinlabs/audit-checklist/blob/master/README.md) addressed **per contract** (Pass / Review / N/A / Informational).

## Scope limits

- These reports are **static reviews** suitable for internal pre-audit triage. They **do not** replace professional audits, formal verification, or economic modeling.
- Solidity **0.8+** provides default checked arithmetic; checklist references to SafeMath are interpreted as “overflow behavior verified under 0.8 semantics / `unchecked` usage.”
- **System-level** risks (relay liveness, miner honesty, COTI MPC correctness) are noted where relevant but are not fully modeled here.

## Folder layout

Paths mirror `contracts/` — e.g. `contracts/fee/PriceOracle.sol` → `ai_audit/fee/PriceOracle/audit-report.md`.

There are **40** reports (one per `.sol` file under `contracts/`).

## CryptoFin checklist mapping

The [CryptoFin Solidity Auditing Checklist](https://github.com/cryptofinlabs/audit-checklist/blob/master/README.md) predates Solidity 0.8. In each `audit-report.md`, the **CryptoFin checklist** section walks **every** checklist theme:

- **Core:** overflow (0.8 checked math vs legacy SafeMath), visibility, warnings, `send` / low-level calls / `var`, external-call risks (reentrancy, DoS/short-circuits, ERC20 quirks, call depth), dependencies, timestamps, rounding, randomness, inputs, loops, push payments, deprecated idioms, `tx.origin`, compiler upgrades.
- **Testing / process:** coverage, unit/integration tests, code freeze.
- **Resilience:** failure modes, invariants, speed bumps, circuit breakers.
- **Process:** external audits, post-audit time.
- **High-risk focus:** public surface, assembly, admin, timing/congestion, value movement, push payments, recent changes.

Reports with **numbered rows** (e.g. test harnesses) map those rows to the same themes for traceability.

## Checklist source

The canonical checklist text is reproduced in `CRYPTOFIN_CHECKLIST_REFERENCE.md` for offline review.
