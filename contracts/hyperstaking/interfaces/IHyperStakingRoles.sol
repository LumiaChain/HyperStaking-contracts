// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

// solhint-disable func-name-mixedcase

/**
 * @title IHyperStakingRoles
 */
interface IHyperStakingRoles {
    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error OnlyDiamondInternal();
    error OnlyStakingManager();
    error OnlyVaultManager();
    error OnlyStrategyManager();
    error OnlyMigrationManager();

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Helper used in external strategies, checks if user has the StrategyManager role
    function hasStrategyManagerRole(address user) external view returns (bool);

    function STAKING_MANAGER_ROLE() external view returns (bytes32);
    function VAULT_MANAGER_ROLE() external view returns (bytes32);
    function STRATEGY_MANAGER_ROLE() external view returns (bytes32);
    function MIGRATION_MANAGER_ROLE() external view returns (bytes32);
}
