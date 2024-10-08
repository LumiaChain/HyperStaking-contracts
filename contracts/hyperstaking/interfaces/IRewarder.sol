// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {} from "../libraries/LibRewarder.sol";

/**
 * @title IRewarder
 * @dev Interface for RewarderFacet
 */
interface IRewarder {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event RewardNotify(
        address indexed strategy,
        address indexed rewardToken,
        uint256 rewardAmount,
        uint256 totalRewardAmount,
        uint64 startTimestamp,
        uint64 endTimestamp
    );

    event RewardClaim(address indexed strategy, address indexed user, uint256 amount);
    event Stop(address strategy, address sender, uint64 timestamp);
    event WithdrawRemaining(address indexed strategy, address receiver, uint256 amount);

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

    function onUpdate(address strategy, address user) external;

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

    function unclaimedTokens(address strategy, address user) external view returns (uint256);

    function balance(address strategy) external view returns (uint256);

    function rewarderExist(address strategy) external view returns (bool);

    // TODO
    // function userRewarderInfo() external view returns();
    // function rewardInfo() external view returns();
    // function rewardPool() external view returns();
}
