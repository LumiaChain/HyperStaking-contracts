// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UserRewardInfo, RewardInfo, RewardPool} from "../libraries/LibRewarder.sol";

/**
 * @title IRewarder
 * @dev Interface for RewarderFacet
 */
interface IRewarder {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event RewardNotify(
        address indexed sender,
        address indexed strategy,
        address indexed rewardToken,
        uint256 rewardAmount,
        uint256 leftover,
        uint64 startTimestamp,
        uint64 endTimestamp
    );

    event RewardClaim(address indexed strategy, address indexed user, uint256 amount);
    event Stop(address sender, address strategy, uint64 timestamp);
    event WithdrawRemaining(address sender, address strategy, address receiver, uint256 amount);

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error ZeroAddress();

    error Stopped();
    error NotStopped();

    error RateTooHigh();
    error StartTimestampPassed();
    error InvalidDistributionRange();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    function claim(address strategy, address user) external returns (uint256 pending);

    function updateUser(address strategy, address user) external;

    function updatePool(address strategy) external;

    /* ========== ACL  ========== */

    function notifyReward(
        address strategy,
        IERC20 rewardToken,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd
    ) external;

    function withdrawRemaining(address strategy, address receiver) external;

    function stop(address strategy) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//


    function balance(address strategy) external view returns (uint256);

    function rewarderExist(address strategy) external view returns (bool);

    /**
     * @notice View function to see unclaimed tokens
     * @param strategy Strategy address
     * @param user Address of user.
     * @return Pending reward for a given user.
     */
    function pendingReward(address strategy, address user) external view returns (uint256);

    function userRewardInfo(
        address strategy,
        address user
    ) external view returns(UserRewardInfo memory);

    function rewardInfo(address strategy) external view returns(RewardInfo memory);

    function rewardPool(address strategy) external view returns(RewardPool memory);
}
