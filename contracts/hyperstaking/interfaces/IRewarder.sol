// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UserRewardInfo, RewardPool} from "../libraries/LibRewarder.sol";

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
        uint256 indexed idx,
        uint256 rewardAmount,
        uint256 leftover,
        uint64 startTimestamp,
        uint64 endTimestamp,
        bool newReward
    );

    event WithdrawRemaining(
        address sender,
        address strategy,
        uint256 idx,
        address receiver,
        uint256 amount
    );

    event Stop(address sender, address strategy, uint256 idx, uint64 timestamp);
    event RewardClaim(address indexed strategy, uint256 idx, address indexed user, uint256 amount);

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error TokenZeroAddress();
    error NoActiveRewardFound();
    error ActiveRewardsLimitReached();

    error Stopped();
    error NotStopped();

    error RewardNotFound();
    error RateTooHigh();
    error StartTimestampPassed();
    error InvalidDistributionRange();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    function claimAll(address strategy, address user) external;

    function claimReward(
        address strategy,
        uint256 idx,
        address user
    ) external returns (uint256 pending);

    function updateActivePools(address strategy, address user) external;

    function updateUser(address strategy, uint256 idx, address user) external;

    function updatePool(address strategy, uint256 idx) external;

    /* ========== ACL  ========== */

    function newRewardDistribution(
        address strategy,
        IERC20 rewardToken,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd
    ) external returns (uint256 idx);

    function notifyRewardDistribution(
        address strategy,
        uint256 idx,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd
    ) external;

    function stop(address strategy, uint256 idx) external;

    function withdrawRemaining(address strategy, uint256 idx, address receiver) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    function balance(address strategy, uint256 idx) external view returns (uint256);

    /**
     * @notice View function to see unclaimed tokens
     * @param strategy Strategy address
     * @param user Address of user.
     * @return Pending reward for a given user.
     */
    function pendingReward(
        address strategy,
        uint256 idx,
        address user
    ) external view returns (uint256);

    function strategyIndex(address strategy) external view returns (uint256);

    function isRewardActive(address strategy, uint256 idx) external view returns (bool);

    function activeRewardList(address strategy) external view returns (uint256[] memory idxList);

    function strategyRewardInfo(
        address strategy,
        uint256 idx
    ) external view returns (IERC20 rewardToken, uint64 stopped);

    function userRewardInfo(
        address strategy,
        uint256 idx,
        address user
    ) external view returns (UserRewardInfo memory);

    function rewardPool(address strategy, uint256 idx) external view returns (RewardPool memory);
}
