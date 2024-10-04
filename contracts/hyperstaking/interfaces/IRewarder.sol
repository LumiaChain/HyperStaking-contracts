// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

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
}
