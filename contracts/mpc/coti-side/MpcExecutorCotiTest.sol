// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

import "./MpcExecutor.sol";
import "./MpcExecutorCotiProxyInbox.sol";

/**
 * @title MpcExecutorCotiTest
 * @notice COTI harness: **direct** `MpcCore` helpers plus **`MpcExecutor`** entrypoints wired to a
 *         `MpcExecutorCotiProxyInbox` (minimal `respond`). Deploy inbox → `MpcExecutor(inbox)` → this contract,
 *         then `registerExecutor` on the inbox (see system test).
 * @dev Avoids nested `new MpcExecutor` in one tx (very large constructor gas on testnet).
 */
contract MpcExecutorCotiTest {
    MpcExecutor public immutable executor;
    MpcExecutorCotiProxyInbox public immutable inboxContract;

    uint256 public lastPlain256;
    uint128 public lastPlain128;
    uint64 public lastPlain64;

    constructor(MpcExecutor _executor, MpcExecutorCotiProxyInbox _inbox) {
        executor = _executor;
        inboxContract = _inbox;
    }

    // --- `MpcExecutor` paths (proxy forwards `mul*FromPlain` so `setPublic` + `mul` run in executor; see `MpcExecutor` natspec) ---

    /// @notice `cOwner` should be the test wallet (MPC user ciphertext owner).
    function executorMul256PublicPlain(uint256 a, uint256 b, address cOwner) external {
        inboxContract.forwardMul256FromPlain(a, b, cOwner);
        ctUint256 memory uc = abi.decode(inboxContract.lastRespondData(), (ctUint256));
        lastPlain256 = MpcCore.decrypt(MpcCore.onBoard(uc));
    }

    function executorMul128PublicPlain(uint128 a, uint128 b, address cOwner) external {
        inboxContract.forwardMul128FromPlain(a, b, cOwner);
        ctUint128 memory uc = abi.decode(inboxContract.lastRespondData(), (ctUint128));
        lastPlain128 = MpcCore.decrypt(MpcCore.onBoard(uc));
    }

    function executorMul64PublicPlain(uint64 a, uint64 b, address cOwner) external {
        inboxContract.forwardMul64FromPlain(a, b, cOwner);
        ctUint64 uc = abi.decode(inboxContract.lastRespondData(), (ctUint64));
        lastPlain64 = MpcCore.decrypt(MpcCore.onBoard(uc));
    }

    // --- Direct `MpcCore` paths (same math, no `respond` / `offBoardCombined`) ---

    function mul256PublicPlain(uint256 a, uint256 b) external returns (uint256 r) {
        gtUint256 memory ga = MpcCore.setPublic256(a);
        gtUint256 memory gb = MpcCore.setPublic256(b);
        gtUint256 memory gr = MpcCore.mul(ga, gb);
        r = MpcCore.decrypt(gr);
        lastPlain256 = r;
    }

    function checkedMul256PublicPlain(uint256 a, uint256 b) external returns (uint256 r) {
        gtUint256 memory ga = MpcCore.setPublic256(a);
        gtUint256 memory gb = MpcCore.setPublic256(b);
        gtUint256 memory gr = MpcCore.checkedMul(ga, gb);
        r = MpcCore.decrypt(gr);
        lastPlain256 = r;
    }

    function mul128PublicPlain(uint128 a, uint128 b) external returns (uint128 r) {
        gtUint128 memory ga = MpcCore.setPublic128(a);
        gtUint128 memory gb = MpcCore.setPublic128(b);
        gtUint128 memory gr = MpcCore.mul(ga, gb);
        r = MpcCore.decrypt(gr);
        lastPlain128 = r;
    }

    function mul64PublicPlain(uint64 a, uint64 b) external returns (uint64 r) {
        gtUint64 ga = MpcCore.setPublic64(a);
        gtUint64 gb = MpcCore.setPublic64(b);
        gtUint64 gr = MpcCore.checkedMul(ga, gb);
        r = MpcCore.decrypt(gr);
        lastPlain64 = r;
    }
}
