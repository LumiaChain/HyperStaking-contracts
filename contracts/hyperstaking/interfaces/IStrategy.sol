// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

/**
 * @title IStrategy
 * @notice Interface for staking strategies used within the protocol.
 * Defines standard functions for managing the allocation and exit of revenue assets.
 */
interface IStrategy {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event Allocate(
        address indexed user,
        uint256 amount,
        uint256 allocation
    );

    event Exit(
        address indexed user,
        uint256 shares,
        uint256 exitAmount
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Allocates a specified amount of the stake to the strategy
     * @param amount_ The amount of the asset to allocate
     * @param user_ The address of the user making the allocation
     * @return allocation The amount successfully allocated
     */
    function allocate(uint256 amount_, address user_) external payable returns (uint256 allocation);

    /**
     * @notice Exits a specified amount of the strategy shares to the vault
     * @param shares_ The amount of the strategy-specific asset (shares) to withdraw
     * @param user_ The address of the user requesting the exit
     * @return exitAmount The amount successfully exited
     */
    function exit(uint256 shares_, address user_) external returns (uint256 exitAmount);
}
