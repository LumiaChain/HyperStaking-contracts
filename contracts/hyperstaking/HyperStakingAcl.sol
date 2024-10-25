// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {IHyperStakingRoles} from "./interfaces/IHyperStakingRoles.sol";

/**
 * @title HyperStakingAcl
 * @dev Defines access control within HyperStaking diamond facets:
 *
 *      Roles:
 *      - `Staking Manager`: Oversees staking operations.
 *      - `Strategy Vault Manager`: Handles strategies and vaults.
 *      - `Rewards Manager`: Manages reward distributions.
 *
 *      Utilizes OpenZeppelin's AccessControlEnumerableUpgradeable, which now supports
 *      EIP-7201 namespace storage, making it compatible with Diamond Proxy architecture.
 *
 *      Includes the `diamondInternal` modifier to restrict access to internal contract calls.
 *      Facets can inherit and use the provided role-based modifiers.
 */
contract HyperStakingAcl is AccessControlEnumerableUpgradeable, IHyperStakingRoles {
    //============================================================================================//
    //                                         Constants                                          //
    //============================================================================================//

    // Define role constants
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 public constant STRATEGY_VAULT_MANAGER_ROLE = keccak256("STRATEGY_VAULT_MANAGER_ROLE");
    bytes32 public constant REWARDS_MANAGER_ROLE = keccak256("REWARDS_MANAGER_ROLE");

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    /// @dev Prevents calling a function from anyone not being the Diamond contract itself.
    modifier diamondInternal() {
        require(msg.sender == address(this), OnlyDiamondInternal());
        _;
    }

    /// @dev Only allows access for the `Staking Manager` role.
    modifier onlyStakingManager() {
        if (!hasRole(STAKING_MANAGER_ROLE, msg.sender)) {
            revert OnlyStakingManager();
        }
        _;
    }

    /// @dev Only allows access for the `Strategy Vault Manager` role.
    modifier onlyStrategyVaultManager() {
        if (!hasRole(STRATEGY_VAULT_MANAGER_ROLE, msg.sender)) {
            revert OnlyStrategyVaultManager();
        }
        _;
    }

    /// @dev Only allows access for the `Rewards Manager` role.
    modifier onlyRewardsManager() {
        if (!hasRole(REWARDS_MANAGER_ROLE, msg.sender)) {
            revert OnlyRewardsManager();
        }
        _;
    }
}
