// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {UserStakingPoolInfo, StakingPoolInfo} from "../libraries/LibStaking.sol";

/**
 * @title IStakingFacet
 * @dev Interface for StakingFacet
 */
interface IStakingFacet {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event StakeDeposit(
        address indexed from,
        uint256 indexed poolId,
        uint256 amount,
        address indexed to
    );

    event StakeWithdraw(
        address indexed from,
        uint256 indexed poolId,
        uint256 amount,
        address indexed to
    );

    event StakingPoolCreate(
        address indexed from,
        address indexed stakeToken,
        uint256 idx,
        uint256 poolId
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    /// @notice Thrown when the provided eth value is incorrect
    error DepositBadValue();

    /// @dev TODO remove
    error Unsupported();

    /// @notice Thrown when failed to transfer ETH value (with call)
    error WithdrawFailedCall();

    /// @notice Thrown when attempting to access a non-existent staking pool
    error PoolDoesNotExist();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Initializes the contract, setting up necessary state variables, // TODO remove
     */
    function init() external;

    /**
     * @notice Deposits a specified amount into a staking pool
     * @param poolId The ID of the staking pool to deposit into
     * @param amount The amount of the token to stake
     * @param to The address receiving the staked tokens (usually the staker's address)
     */
    function stakeDeposit(uint256 poolId, uint256 amount, address to) external payable;

    /**
     * @notice Withdraws a specified amount from a staking pool
     * @param poolId The ID of the staking pool to withdraw from
     * @param amount The amount of the staked token to withdraw
     * @param to The address to receive the withdrawn tokens
     */
    function stakeWithdraw(uint256 poolId, uint256 amount, address to) external;


    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /**
     * @notice Returns the user's share of the total pool allocation
     * @param poolId The ID of the staking pool
     * @param user The address of the user
     * @return The user's share of the pool, represented as a scaled percentage (using 1e18 as a precision factor)
     */
    function userShare(uint256 poolId, address user) external view returns (uint256);

    /**
     * @notice Returns information about a user's staking position in a specific pool
     * @param poolId The ID of the staking pool
     * @param user The address of the user
     * @return A struct containing the user's staking information
     */
    function userInfo(
        uint256 poolId,
        address user
    ) external view returns (UserStakingPoolInfo memory);

    /**
     * @notice Returns information about a specific staking pool
     * @param poolId The ID of the staking pool
     * @return A struct containing details about the pool
     */
    function poolInfo(uint256 poolId) external view returns (StakingPoolInfo memory);

    /**
     * @notice Returns the address of the native token
     * @dev For internal use, an address is generated, e.g., for ETH
     * @return The address of the native token
     */
    function nativeTokenAddress() external pure returns (address);

    /**
     * @notice Generates a unique pool ID for a specific staking token and pool index
     * @param stakeToken The address of the token being staked
     * @param idx The index of the pool for that token (starting from 0)
     * @return The unique ID for the pool
     */
    function generatePoolId(address stakeToken, uint96 idx) external pure returns (uint256);
}
