// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

/**
 * @notice Info of each MasterChef user.
 * amount LP token amount the user has provided.
 * rewardPerTokenPaid The amount of reward tokens not available to claim.
 * tokensUnclaimed The amount of reward unclaimed tokens, waiting to be claimed by user.
 */
struct UserRewardInfo {
    uint256 amount;
    uint256 rewardPerTokenPaid;
    uint256 tokensUnclaimed;
}

/**
 * @notice General information of each reward.
 * @dev Contains details about the reward token and distribution periods.
 * @param rewardToken The address of the reward token.
 * @param stopped Timestamp when the distribution was stopped (0 if active).
 * @param distributionStart Start timestamp of the current or finished distribution.
 * @param distributionEnd End timestamp of the current or finished distribution.
 */
struct RewardInfo {
    IERC20 rewardToken;
    uint64 stopped;
    uint64 distributionStart;
    uint64 distributionEnd;
}

/**
 * @notice Reward variables for the pool.
 * @dev Tracks the distribution rate and the accumulated reward per token.
 * @param tokensPerSecond Distribution rate of the token per second.
 * @param accTokenPerShare Accumulated reward per token (scaled).
 * @param lastRewardTimestamp The last time rewards were distributed to the pool.
 */
struct RewardPool {
    uint256 tokensPerSecond;
    uint256 accTokenPerShare;
    uint64 lastRewardTimestamp;
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct RewarderStorage {
    /// @notice Mapping that stores reward distribution info for each strategy.
    /// @dev Maps a strategy address to its corresponding RewardInfo details.
    mapping(address strategy => RewardInfo) rewardsInfo;

    /// @notice Mapping that stores reward pool state for each strategy.
    /// @dev Maps a strategy address to its corresponding RewardPool state.
    mapping(address strategy => RewardPool) rewardPools;

    /// @notice Info of each user that stakes tokens into strategy
    mapping(address strategy => mapping(address user => UserRewardInfo)) userInfo;
}

library LibRewarder {
    bytes32 constant internal REWARDER_STORAGE_POSITION = keccak256("hyperstaking-rewarder.storage");

    // Considers edge cases for token reward calculation: preventing overflow with max values
    // and avoiding rounding to zero with minimal values. This precision value is a solid compromise
    uint256 constant internal REWARD_PRECISION = 1e36;

    function diamondStorage() internal pure returns (RewarderStorage storage s) {
        bytes32 position = REWARDER_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
