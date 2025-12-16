// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {VaultInfo} from "../libraries/LibHyperStaking.sol";

/**
 * @title IHyperFactory
 */
interface IHyperFactory {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event VaultCreate(
        address indexed from,
        address strategy,
        address indexed stakeCurrency,
        address indexed revenueAsset,
        string vaultTokenName,
        string vaultTokenSymbol,
        uint8 decimals
    );

    event VaultEnabledSet(address indexed strategy, bool enabled);

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    /// @notice Thrown when attempting to create a vault using the same strategy
    error VaultAlreadyExist();

    /// @notice Thrown when attempting to enable non existing vault
    error VaultDoesNotExist(address strategy);

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    // ========= Managed ========= //

    /**
     * @notice Adds a new strategy and links it to a specific staking currency and vault
     * @dev Sets up the strategy with an associated asset,
     *      payable for dispatching interchain "RouteRegistry" messages to other chain
     * @param strategy The existing strategy (IStrategy) for which a new vault will be created
     * @param vaultTokenName The name of the vault token to be deployed
     * @param vaultTokenSymbol The symbol of the vault token to be deployed
     */
    function addStrategy(
        address strategy,
        string memory vaultTokenName,
        string memory vaultTokenSymbol
    ) external payable;

    /**
     * @notice Enables or disables strategy
     * @param strategy The strategy address
     * @param enabled True to enable, false to disable
     */
    function setStrategyEnabled(address strategy, bool enabled) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /**
     * @notice Retrieves information about a specific vault associated with a strategy
     * @param strategy The address of the strategy for which to retrieve vault information
     * @return A VaultInfo struct containing details about the vault
     */
    function vaultInfo(address strategy) external view returns (VaultInfo memory);

    /// @notice Helper to easily quote the dispatch fee for addStrategy
    function quoteAddStrategy(
        address strategy,
        string memory vaultTokenName,
        string memory vaultTokenSymbol
    ) external view returns (uint256);
}
