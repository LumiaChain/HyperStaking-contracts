// SPDX-License-Identifier: UNLICENSED
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
        address asset,
        address vaultToken
    );

    event DirectVaultCreate(
        address indexed from,
        address strategy
    );

    event VaultEnabledSet(address indexed strategy, bool enabled);

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    /// @notice Thrown when attempting to create a vault using the same strategy
    error VaultAlreadyExist();

    /// @notice Thrown when attempting to add a non-direct strategy as direct
    error NotDirectStrategy(address strategy);

    /// @notice Thrown when attempting to enable non existing vault
    error VaultDoesNotExist(address strategy);

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    // ========= Managed ========= //

    /**
     * @notice Adds a new strategy and links it to a specific staking currency and vault
     * @dev Sets up the strategy with an associated asset and a revenue fee for Tier 1 users
     *      payable for dispatching interchain "TokenDeploy" messages to other chains
     * @param strategy The address of the strategy being added
     * @param vaultTokenName The name of the vault token to be deployed
     * @param vaultTokenSymbol The symbol of the vault token to be deployed
     * @param tier1RevenueFee The revenue fee for Tier 1 users, specified as an 18-decimal fraction
     */
    function addStrategy(
        address strategy,
        string memory vaultTokenName,
        string memory vaultTokenSymbol,
        uint256 tier1RevenueFee
    ) external payable;

    /**
     * @notice Adds a new direct strategy and links it to a specific staking currency and vault
     * @dev Sets up the direct strategy which requires only strategy address
     * @param strategy The address of the strategy being added
     */
    function addDirectStrategy(
        address strategy
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
}
