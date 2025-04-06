// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ITokensRewarder} from "./ITokensRewarder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IMasterChef
 * @dev Interface for MasterChefFacet
 */

interface IMasterChef {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event Set(address indexed token, ITokensRewarder indexed rewarder);

    event Deposit(address indexed user, address indexed token, uint256 amount);

    event Withdraw(address indexed user, address indexed token, uint256 amount);

    event TokenStakeLimitSet(address indexed stakeToken, uint256 newLimit);

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error BadRewarder();
    error ZeroStakeAmount();
    error ZeroWithdrawAmount();
    error ExceededWithdraw();

    error ZeroTokenAddress();
    error ReplaceUnfinalizedRewarder();
    error InvalidStakeToken(address stakeToken);

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Deposit stake tokens to MasterChef
     * @param token Address of the stake token
     * @param amount Amount to deposit
     */
    function stake(address token, uint256 amount) external;

    /**
     * @notice Withdraw stake tokens from MasterChef
     * @param token Address of the stake token
     * @param amount Amount to withdraw
     */
    function withdraw(address token, uint256 amount) external;

    /**
     * @notice Claim pending rewards for a specific stake token for a given user
     * @param token Address of the stake token
     * @param user Address of the user claiming rewards
     */
    function claim(address token, address user) external;

    /**
     * @notice Claim pending rewards from multiple rewarders for a given user
     * @dev Rewarders should exist and not be finalized
     * @param rewarders Array of addresses of rewarders
     * @param user Address of the user claiming rewards
     */
    function claimMultipleRewarders(address[] calldata rewarders, address user) external;

    /**
     * @notice Sets the new `TokensRewarder` contract for a stake token
     * @dev For an already existing rewarder, require it to be finalized
     * @param token Address of the stake token
     * @param rewarder Address of the rewarder or zero address
     */
    function set(address token, ITokensRewarder rewarder) external;

    /**
     * @notice Updates the total stake limit for a given stake token
     * @dev If `limit` == 0 there is effectively no maximum stake limit
     */
    function setTokenStakeLimit(address stakeToken, uint256 limit) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /**
     * @notice View function to see pending tokens
     * @param token Address of the stake token
     * @param distributionIdx Index of the reward distribution within TokensRewarder
     * @param user Address of user
     * @return rewarder Address of rewarder contract
     * @return rewardToken Address of the reward token
     * @return pendingReward Amount of pendingReward/unclaimed reward
     */
    function rewardData(address token, uint256 distributionIdx, address user)
        external
        view
        returns (ITokensRewarder rewarder, IERC20 rewardToken, uint256 pendingReward);

    /**
     * @notice Retrieves the rewarder contract for a given stake token
     */
    function getRewarder(address stakeToken) external view returns (ITokensRewarder);

    /**
     * @notice Retrieves the amount of tokens a user has staked for a given stake token
     */
    function getUserStake(address stakeToken, address user) external view returns (uint256);

    /**
     * @notice Retrieves the total amount of tokens staked for a given stake token
     */
    function getTotalStake(address stakeToken) external view returns (uint256);

    /**
     * @notice Retrieves the maximum allowed total stake for a given token
     */
    function getTokenStakeLimit(address stakeToken) external view returns (uint256);
}

