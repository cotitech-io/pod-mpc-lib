# Audit report: `contracts/mpc/coti-side/MpcExecutorCotiProxyInbox.sol`

**Solidity:** ^0.8.19  
**Purpose:** Test / harness

## Introduction

Minimal “inbox” that registers one executor and forwards `mul*FromPlain` plus records `respond` data. **Not a production inbox.**

## Vulnerabilities


| ID    | Description                                                                                              | Severity           |
| ----- | -------------------------------------------------------------------------------------------------------- | ------------------ |
| MPX-1 | `**registerExecutor` has no access control** — first caller wins → **DoS or hijack** in shared testnets. | High (test misuse) |
| MPX-2 | `**forwardMul*FromPlain`**: Anyone can call if executor set — **test only**.                             | High (test misuse) |


## Recommendations

- **Do not deploy to mainnet** as security boundary.
- Add `onlyOwner` or hardcoded expected deployer for persistent testnets.

## Conclusion

**Unsafe as production.** Suitable for controlled tests only.

---

## CryptoFin checklist — item by item


| Item             | Status            | Notes                     |
| ---------------- | ----------------- | ------------------------- |
| Access control   | **Fail** for prod | Open registration         |
| External calls   | Review            | Forwards to `MpcExecutor` |
| Input validation | Fail              | No auth on register       |
| Tests            | Pass              | Intended harness          |


