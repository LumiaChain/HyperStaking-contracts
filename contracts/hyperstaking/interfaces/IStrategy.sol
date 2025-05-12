// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {Currency} from "../libraries/CurrencyHandler.sol";

/**
 * @title IStrategy
 * @notice Interface for staking strategies used within the protocol
 * Defines standard functions for managing the allocation and exit of revenue assets
 */
interface IStrategy {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event Allocate(
        address indexed user,
        uint256 stakeAmount,
        uint256 assetAllocation
    );

    event Exit(
        address indexed user,
        uint256 assetAllocation,
        uint256 exitStakeAmount
    );

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Allocates a specified amount of the stake to the strategy
     * @param stakeAmount_ The amount of stake received for allocation
     * @param user_ The address of the user making the allocation
     * @return allocation The amount successfully allocated
     */
    function allocate(
        uint256 stakeAmount_,
        address user_
    ) external payable returns (uint256 allocation);

    /**
     * @notice Exits a specified amount of the strategy shares to the vault
     * @param assetAllocation_ The amount of the strategy-specific asset (shares) to withdraw
     * @param user_ The address of the user requesting the exit
     * @return exitAmount The amount successfully exited
     */
    function exit(uint256 assetAllocation_, address user_) external returns (uint256 exitAmount);

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /**
     * @notice Indicates whether the strategy is a DirectStakeStrategy
     * @return Always returns `false` in non-direct stake strategies
     */
    function isDirectStakeStrategy() external view returns (bool);

    /// @return Currency used for allocation into strategy (stake)
    function stakeCurrency() external view returns(Currency calldata);

    /// @return The address of the revenue-accumulating asset (allocation asset)
    function revenueAsset() external view returns(address);

    /// @dev Preview the asset allocation for a given stake amount
    function previewAllocation(uint256 stakeAmount_) external view returns (uint256 allocation);

    /// @dev Preview the stake amount that would be received in exchange for a given allocation
    function previewExit(uint256 assetAllocation_) external view returns (uint256 stakeAmount);
}
