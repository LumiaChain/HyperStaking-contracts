// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {UserStrategyInfo, StrategyInfo} from "../libraries/LibReserveStrategy.sol";

/**
 * @title IStakingStrategy
 * @notice Interface for staking strategies used within the protocol.
 * Defines standard functions for managing the allocation and withdrawal of assets.
 */
interface IStakingStrategy {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event Allocate(uint256 strategyId, uint256 poolId, uint256 amount);

    event Exit(uint256 strategyId, uint256 poolId, uint256 amount, int256 revenue);

    event RevenueAssetSupply(uint256 strategyId, uint256 poolId, uint256 amount);

    event RevenueAssetWithdraw(uint256 strategyId, uint256 poolId, uint256 amount);

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    /// @notice Thrown when attempting to allocate to a non-existent strategy
    error StrategyDoesNotExist();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Initializes the contract, creates test pool, // TODO remove
     */
    function init(uint256 poolId) external;

    /**
     * @notice Allocates a specified amount of the stake token from staking pool strategy
     * @param amount The amount of the asset to allocate from the reserve
     */
    function allocate(uint256 strategyId, uint256 poolId, uint256 amount) external;

    /**
     * @notice Withdraws a specified amount of the token from the reserve back to the staking pool
     * @param amount The amount of the asset to withdraw and return to the reserve
     */
    function exit(uint256 strategyId, uint256 poolId, uint256 amount) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /**
     * @notice Returns the user's share of the total strategy allocation
     * @param strategyId The ID of the strategy
     * @param user The address of the user
     * @return The user's share of the strategy, scaled percentage (1e18 as a precision factor)
     */
    function userShare(uint256 strategyId, address user) external view returns (uint256);

    /**
     * @notice Returns detailed information about the user's position in a specific strategy
     * @param strategyId The ID of the strategy
     * @param user The address of the user
     * @return A struct containing the user's information in the strategy
     */
    function userInfo(
        uint256 strategyId,
        address user
    ) external view returns (UserStrategyInfo memory);

    /**
     * @notice Returns general information about a specific strategy
     * @param strategyId The ID of the strategy
     * @return A struct containing details about the strategy
     */
    function strategyInfo(uint256 strategyId) external view returns (StrategyInfo memory);

    /**
     * @notice Generates a unique strategy ID for a specific staking pool and index
     * @param poolId The base ID of the staking pool
     * @param idx The index for the strategy for that staking pool
     * @return The unique ID for the strategy
     */
    function generateStrategyId(uint256 poolId, uint256 idx) external pure returns (uint256);
}
