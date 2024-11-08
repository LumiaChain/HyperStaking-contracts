// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {UserVaultInfo, VaultInfo} from "../libraries/LibStrategyVault.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title IStrategyVault
 */
interface IStrategyVault {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event VaultCreate(
        address indexed from,
        uint256 indexed poolId,
        address strategy,
        address assert,
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
     * @param poolId The ID of the staking pool to assign this strategy to
     * @param strategy The address of the strategy being added
     * @param asset The ERC20-compliant asset associated with the strategy
     * @param tier1RevenueFee The revenue fee for Tier 1 users, specified as an 18-decimal fraction
     */
    function addStrategy(
        uint256 poolId,
        address strategy,
        IERC20Metadata asset,
        uint256 tier1RevenueFee
    ) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    function userVaultInfo(
        address strategy,
        address user
    ) external view returns (UserVaultInfo memory);

    function vaultInfo(address strategy) external view returns (VaultInfo memory);
}
