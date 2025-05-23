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
     * @dev  Direct stake strategies bypass all yield‐generating logic and
     *       exist solely to allow 1:1 deposits into the vault without a
     *       separate strategy usage. They:
     *         - Store currency info to remain compatible with the vault
     *         - Always revert on `allocate(...)`, `exit(...)`, and any
     *           preview functions
     * @return Always returns `true` for direct stake strategies, `false` otherwise
     */
    function isDirectStakeStrategy() external view returns (bool);

    /**
     * @notice Returns true if this stake strategy is an integrated strategy
     * @dev An integrated strategy delegates all asset movements (ERC-20 tokens or native currency)
     *      to the IntegrationFacet within the same diamond. As a result:
     *        - The strategy never calls `transferFrom` or any pull for ERC20 tokens
     *        - It never needs to handle native currency transfers itself
     *        - It does not manage any ERC20 approvals itself
     *        - Both `allocate(...)` and `exit(...)` invoke the IntegrationFacet
     *          directly to move tokens internally within the diamond
     */
    function isIntegratedStakeStrategy() external view returns (bool);

    /// @return Currency used for allocation into strategy (stake)
    function stakeCurrency() external view returns(Currency calldata);

    /// @return The address of the revenue-accumulating asset (allocation asset)
    function revenueAsset() external view returns(address);

    /// @dev Preview the asset allocation for a given stake amount
    function previewAllocation(uint256 stakeAmount_) external view returns (uint256 allocation);

    /// @dev Preview the stake amount that would be received in exchange for a given allocation
    function previewExit(uint256 assetAllocation_) external view returns (uint256 stakeAmount);
}
