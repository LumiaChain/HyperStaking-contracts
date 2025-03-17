// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

// solhint-disable func-name-mixedcase

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {IHyperStakingRoles} from "./interfaces/IHyperStakingRoles.sol";

import {LibAcl} from "./libraries/LibAcl.sol";

/**
 * @title HyperStakingAcl
 * @dev Defines access control within HyperStaking diamond facets:
 *
 *      Roles:
 *      - `Staking Manager`: Oversees staking operations
 *      - `Vault Manager`: Handles vaults
 *      - `Strategy Manager`: Handles external strategies
 *      - `Migration Manager`: Handles migrations
 *
 *      Utilizes OpenZeppelin's AccessControlEnumerableUpgradeable, which now supports
 *      EIP-7201 namespace storage, making it compatible with Diamond Proxy architecture
 *
 *      Includes the `diamondInternal` modifier to restrict access to internal contract calls
 *      Facets can inherit and use the provided role-based modifiers
 */
contract HyperStakingAcl is AccessControlEnumerableUpgradeable, IHyperStakingRoles {

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    /// @dev Prevents calling a function from anyone not being the Diamond contract itself
    modifier diamondInternal() {
        require(msg.sender == address(this), OnlyDiamondInternal());
        _;
    }

    /// @dev Only allows access for the `Staking Manager` role
    modifier onlyStakingManager() {
        if (!hasRole(STAKING_MANAGER_ROLE(), msg.sender)) {
            revert OnlyStakingManager();
        }
        _;
    }

    /// @dev Only allows access for the `Vault Manager` role
    modifier onlyVaultManager() {
        if (!hasRole(VAULT_MANAGER_ROLE(), msg.sender)) {
            revert OnlyVaultManager();
        }
        _;
    }

    /// @dev Only allows access for the `Strategy Manager` role
    modifier onlyStrategyManager() {
        if (!hasRole(STRATEGY_MANAGER_ROLE(), msg.sender)) {
            revert OnlyStrategyManager();
        }
        _;
    }

    /// @dev Only allows access for the `Strategy Manager` role
    modifier onlyMigrationManager() {
        if (!hasRole(MIGRATION_MANAGER_ROLE(), msg.sender)) {
            revert OnlyMigrationManager();
        }
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= View ========= //

    /// @inheritdoc IHyperStakingRoles
    function hasStrategyManagerRole(address account) external view returns (bool) {
        return hasRole(STRATEGY_MANAGER_ROLE(), account);
    }

    // ---

    function STAKING_MANAGER_ROLE() public pure returns (bytes32) {
        return LibAcl.STAKING_MANAGER_ROLE;
    }

    function VAULT_MANAGER_ROLE() public pure returns (bytes32) {
        return LibAcl.VAULT_MANAGER_ROLE;
    }

    function STRATEGY_MANAGER_ROLE() public pure returns (bytes32) {
        return LibAcl.STRATEGY_MANAGER_ROLE;
    }

    function MIGRATION_MANAGER_ROLE() public pure returns (bytes32) {
        return LibAcl.MIGRATION_MANAGER_ROLE;
    }
}
