// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {VaultTier1} from "../libraries/LibStrategyVault.sol";

/**
 * @title ITierVault
 * @dev Interface for Tier1VaultFacet
 */
interface ITier1Vault {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event Tier1Join(
        uint256 indexed poolId,
        address indexed strategy,
        address indexed user,
        uint256 stake,
        uint256 allocation
    );

    event Tier1Leave(
        uint256 indexed poolId,
        address indexed strategy,
        address indexed user,
        uint256 stake,
        uint256 allocation,
        uint256 revenueFee
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    /// @notice Thrown when attempting to set invalid revenue fee value for tier1
    error InvalidRevenueFeeValue();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Join Tier 1 for a specified strategy by staking a certain amount
     * @param strategy The strategy for which the user is joining Tier 1
     * @param user The address of the user
     * @param stake The stake amount of tokens the user use to join Tier 1
     */
    function joinTier1(address strategy, address user, uint256 stake) external payable;

    /**
     * @notice Leave Tier 1 for a specified strategy and withdraw a certain stake amount
     * @param strategy The strategy from which the user is leaving Tier 1
     * @param user The address of the user
     * @param stake The amount of initial stake the user is withdrawing from Tier 1
     * @return The total withdrawal amount, including the stake, generated revenue, after fees
     */
    function leaveTier1(address strategy, address user, uint256 stake) external returns (uint256);

    /**
     * @notice Sets the revenue fee for users in a specified strategy
     * @param strategy The strategy for which the Tier 1 revenue fee is being set
     * @param revenueFee The new revenue fee, specified as an 18-decimal fraction
     */
    function setRevenueFee(address strategy, uint256 revenueFee) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /**
     * @notice Retrieves Tier 1 vault information for a specified strategy
     * @param strategy The address of the strategy
     * @return The VaultTier1 struct containing information about this specific tier
     */
    function vaultTier1Info(address strategy) external view returns (VaultTier1 memory);

    /**
     * @notice Retrieves the total contribution of a user for a specified strategy
     * @param strategy The address of the strategy
     * @param user The address of the user
     * @return The user's total contribution amount for the specified strategy (18-dec fraction)
     */
    function userContribution(address strategy, address user) external view returns (uint256);

    /**
     * @notice Returns the revenue for a user based on the current allocation price of a strategy
     * @dev Returns 0 if the allocation price has not increased
     * @param strategy The strategy address
     * @param user The user's address
     * @return revenue The calculated revenue for the user
     */
    function userRevenue(address strategy, address user) external view returns (uint256 revenue);
}
