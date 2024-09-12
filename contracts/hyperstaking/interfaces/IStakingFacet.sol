// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {UserInfo, PoolInfo} from "../libraries/LibStaking.sol";

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

    function userInfo(uint256 poolId, address user) external view returns (UserInfo memory);

    function poolInfo(uint256 poolId) external view returns (PoolInfo memory);

    function nativeTokenAddress() external pure returns (address);

    function generatePoolId(address stakeToken, uint96 idx) external pure returns (uint256);
}
