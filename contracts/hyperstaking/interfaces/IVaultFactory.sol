// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {VaultInfo} from "../libraries/LibStrategyVault.sol";
import {Currency} from "../libraries/CurrencyHandler.sol";

/**
 * @title IVaultFactory
 */
interface IVaultFactory {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event VaultCreate(
        address indexed from,
        uint256 indexed poolId,
        address strategy,
        address asset,
        address vaultToken
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    /// @notice Thrown when attempting to create a vault using the same strategy
    error VaultAlreadyExist();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    // ========= Managed ========= //

    /**
     * @notice Adds a new strategy and links it to a specific staking pool
     * @dev Sets up the strategy with an associated asset and a revenue fee for Tier 1 users
     *      payable for dispatching interchain "TokenDeploy" messages to other chains
     *
     * @param currency The currency which will be used as stake for this strategy
     * @dev For native coin use currency with address(0) token.
     *
     * @param poolId The ID of the staking pool to assign this strategy to
     * @param strategy The address of the strategy being added
     * @param vaultTokenName The name of the vault token to be deployed
     * @param vaultTokenSymbol The symbol of the vault token to be deployed
     * @param tier1RevenueFee The revenue fee for Tier 1 users, specified as an 18-decimal fraction
     */
    function addStrategy(
        uint256 poolId,
        Currency calldata currency,
        address strategy,
        string memory vaultTokenName,
        string memory vaultTokenSymbol,
        uint256 tier1RevenueFee
    ) external payable;

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
