// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

/**
 * @title IMigration
 * @dev Interface for MigrationFacet
 */
interface IMigration {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event StrategyMigrated(
        address indexed manager,
        address fromStrategy,
        address toStrategy,
        uint256 amount
    );

    //===========================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error ZeroAmount();
    error SameStrategy();
    error DirectStrategy();

    error InvalidStrategy(address strategy);
    error InvalidCurrency();
    error InsufficientAmount();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Migrates staked currency or shares from one strategy to another
     * @dev Allows partial migration of a specified amount between two strategies
     *      The `payable` modifier is included to support potential interchain execution
     * @param fromStrategy The address of the strategy to migrate from
     * @param toStrategy The address of the strategy to migrate to
     * @param amount The amount of staked assets to migrate
     */
    function migrateStrategy(
        address fromStrategy,
        address toStrategy,
        uint256 amount
    ) external payable;
}
