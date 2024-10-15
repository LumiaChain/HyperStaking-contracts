// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

/**
 * @notice Info of each MasterChef user
 * rewardPerTokenPaid The amount of reward tokens not available to claim
 * rewardUnclaimed The amount of reward unclaimed tokens, waiting to be claimed by user
 */
struct UserRewardInfo {
    uint256 rewardPerTokenPaid;
    uint256 rewardUnclaimed;
}

/**
 * @notice Reward variables for the pool
 * @dev Tracks the distribution rate and the accumulated reward per token
 * @param tokensPerSecond Distribution rate of the token per second
 * @param rewardPerToken Last updated amount of reward per staked token
 * @param distributionStart Start timestamp of the current or finished distribution
 * @param distributionEnd End timestamp of the current or finished distribution
 * @param lastRewardTimestamp The last time rewards were distributed to the pool
 */
struct RewardPool {
    uint256 tokensPerSecond;
    uint256 rewardPerToken;
    uint64 distributionStart;
    uint64 distributionEnd;
    uint64 lastRewardTimestamp;
}

/**
 * @notice Represents reward distribution data for a specific staking strategy
 * @dev Combines information on reward, user-specific reward details, and the reward pool state
 * @param rewardToken The address of the reward token
 * @param stopped Timestamp when the distribution was stopped (0 if active)
 * @param info Contains reward distribution information for the strategy
 * @param user Holds reward data for each user staking tokens in the strategy
 * @param pool Tracks the reward pool's state for the strategy
 */
struct StrategyReward {
    IERC20 rewardToken;
    uint64 stopped;
    mapping(address user => UserRewardInfo) users;
    RewardPool pool;
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct RewarderStorage {
    /// @notice Tracks the latest index for each individual strategy, starting from 0 by default
    /// @dev This index represents the total number of rewards created for a given strategy.
    ///      Each time a new reward is added to a strategy, this index is incremented.
    mapping(address strategy => uint256) strategyIndex;

    /// @notice Mapping from strategy to an array of reward distributions
    /// @dev Tracks all reward distributions associated with a given strategy
    mapping(address strategy => mapping(uint256 idx => StrategyReward)) strategyRewards;

    /// @notice List of active reward IDs for each strategy
    /// @dev Each strategy should not exceed the defined limit (REWARDS_PER_STRATEGY_LIMIT)
    mapping(address strategy => uint256[]) activeRewardLists;

    /// @notice Optimized mapping for cheap access to active rewards
    /// @dev Maps strategy and reward idx to a boolean indicating whether the reward is active
    mapping(address strategy => mapping(uint256 idx => bool)) activeRewards;
}

library LibRewarder {
    bytes32 constant internal REWARDER_STORAGE_POSITION = keccak256("hyperstaking-rewarder.storage");

    // Considers edge cases for token reward calculation: preventing overflow with max values
    // and avoiding rounding to zero with minimal values. This precision value is a solid compromise
    uint256 constant internal REWARD_PRECISION = 1e36;

    // Maximum number of rewards allowed per strategy
    uint8 constant internal REWARDS_PER_STRATEGY_LIMIT = 5;

    function diamondStorage() internal pure returns (RewarderStorage storage s) {
        bytes32 position = REWARDER_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
