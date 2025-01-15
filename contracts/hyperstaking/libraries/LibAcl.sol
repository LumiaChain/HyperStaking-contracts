// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

library LibAcl {

    // Define role constants
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 public constant STRATEGY_VAULT_MANAGER_ROLE = keccak256("STRATEGY_VAULT_MANAGER_ROLE");
    bytes32 public constant REWARDS_MANAGER_ROLE = keccak256("REWARDS_MANAGER_ROLE");
}
