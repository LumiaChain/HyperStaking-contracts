// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {UserStrategyInfo, StrategyInfo, RevenueAsset} from "../libraries/LibReserveStrategy.sol";

/**
 * @title IStakingStrategy
 * @notice Interface for staking strategies used within the protocol.
 * Defines standard functions for managing the allocation and withdrawal of assets.
 */
interface IStakingStrategy {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event Allocate(
        uint256 indexed strategyId,
        uint256 indexed poolId,
        address indexed user,
        uint256 amount
    );
    event Exit(
        uint256 indexed strategyId,
        uint256 indexed poolId,
        address indexed user,
        uint256 amount,
        int256 revenue
    );

    event RevenueAssetSupply(
        address indexed from,
        uint256 indexed strategyId,
        address indexed asset,
        uint256 amount
    );
    event RevenueAssetWithdraw(
        address indexed to,
        uint256 indexed strategyId,
        address indexed asset,
        uint256 amount
    );

    event StrategyCreate(
        address indexed from,
        uint256 indexed poolId,
        uint256 idx,
        uint256 strategyId
    );

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
    function init(uint256 poolId, address revenueAsset, uint256 testAssetPrice) external;

    /**
     * @notice Allocates a specified amount of the stake token from staking pool strategy
     * @param amount The amount of the asset to allocate from the reserve
     */
    function allocate(uint256 strategyId, address user, uint256 amount) external;

    /**
     * @notice Withdraws a specified amount of the token from the reserve back to the staking pool
     * @param amount The amount of the asset to withdraw and return to the reserve
     */
    function exit(
        uint256 strategyId,
        address user,
        uint256 amount
    ) external returns (uint256 exitAmount);

    // TODO ACL
    function supplyRevenueAsset(uint256 strategyId, uint256 amount) external;
    function withdrawRevenueAsset(uint256 strategyId, uint256 amount) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /**
     * @notice Returns detailed information about the user's position in a specific strategy
     * @param strategyId The ID of the strategy
     * @param user The address of the user
     * @return A struct containing the user's information in the strategy
     */
    function userStrategyInfo(
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
     * @notice Returns information about the revenue-generating asset for a specific strategy
     * @param strategyId The ID of the strategy
     * @return A struct containing details about the revenue asset for the given strategy
     */
    function revenueAssetInfo(uint256 strategyId) external view returns (RevenueAsset memory);

    /**
     * @notice Returns the user's share of the total strategy allocation
     * @param strategyId The ID of the strategy
     * @param user The address of the user
     * @return The user's share of the strategy, represented as a scaled percentage
     *         (using 1e18 as a precision factor)
     */
    function userStrategyShare(uint256 strategyId, address user) external view returns (uint256);

    // calculate exit amount based on strategy exit amount and revenue asset allocation
    function calcUserExitAmount(
        uint256 strategyId,
        address user,
        uint256 amount
    ) external view returns (uint256);

    /**
     * @notice Generates a unique strategy ID for a specific staking pool and index
     * @param poolId The base ID of the staking pool
     * @param idx The index for the strategy for that staking pool
     * @return The unique ID for the strategy
     */
    function generateStrategyId(uint256 poolId, uint256 idx) external pure returns (uint256);
}
