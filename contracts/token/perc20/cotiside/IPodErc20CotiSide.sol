// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

interface IPodErc20CotiSide {
    /// @notice Owner-only on the implementation; mints plain amount into the COTI garbled balance for `to`.
    function mint(address to, uint256 amount) external;

    function syncBalances(address[] calldata accounts) external;
    function transfer(address from, address to, gtUint256 calldata value) external;
    function transferFrom(address from, address to, gtUint256 calldata value) external;
    function approve(address owner, address spender, gtUint256 calldata value) external;
    function burn(address from, gtUint256 calldata value) external;
}