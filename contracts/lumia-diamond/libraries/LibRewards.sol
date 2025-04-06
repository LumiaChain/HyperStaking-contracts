// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ITokensRewarder} from "../interfaces/ITokensRewarder.sol";

//================================================================================================//
//                               Tokens Rewarder Types                                            //
//================================================================================================//

/**
 * @notice Info of each MasterChef user
 * stakeAmount last updated user stake amount
 * rewardPerTokenPaid The amount of reward tokens not available to claim
 * rewardUnclaimed The amount of reward unclaimed tokens, waiting to be claimed by user
 */
struct UserRewardInfo {
    uint256 stakeAmount; // TODO update this
    uint256 rewardPerTokenPaid;
    uint256 rewardUnclaimed;
}

/**
 * @notice Reward variables for the pool
 * @dev Tracks the distribution rate and the accumulated reward per token
 * @param tokensPerSecond Distribution rate of the token per second
 * @param rewardPerToken Last updated amount of reward per staking token
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
 * @notice Represents reward distribution data for a specific reward token
 * @param rewardToken The address of the reward token
 * @param finalized Timestamp when the distribution was finalized (0 if active)
 * @notice users Mapping that tracks user reward information for each staking token
 * @param pool Tracks the reward pool's state
 */
struct RewardDistribution {
    IERC20 rewardToken;
    uint64 finalizeTimestamp;
    mapping(address user => UserRewardInfo) users;
    RewardPool pool;
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct RewardsStorage {
    /// @notice Info of each MasterChef tokens reward pool assigned to a stake token
    mapping(address => ITokensRewarder) tokenRewarders;

    /// @notice Amount of staked tokens per user, stakeToken -> user
    mapping(address => mapping(address => uint256)) usersTokenStake;

    /// @notice Total Amount of staked tokens
    mapping(address => uint256) tokenTotalStake;

    // TODO
    mapping(address => uint256) tokenTotalStakeLimits;
}

library LibRewards {
    bytes32 constant internal REWARDS_STORAGE_POSITION = keccak256("lumia-rewards.storage");

    uint256 constant internal REWARD_PRECISION = 1e36;

    // Maximum number of concurrent rewards allowed per staking token
    uint8 constant internal REWARDS_PER_STAKING_LIMIT = 10;

    function diamondStorage() internal pure returns (RewardsStorage storage s) {
        bytes32 position = REWARDS_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}

// ---

// library LibRewarder {
//     bytes32 constant internal REWARDER_STORAGE_POSITION = keccak256("lumia-rewarder.storage");
//
//     // Considers edge cases for token reward calculation: preventing overflow with max values
//     // and avoiding rounding to zero with minimal values. This precision value is a solid compromise
//     uint256 constant internal REWARD_PRECISION = 1e36;
//
//     // Maximum number of concurrent rewards allowed per staking token
//     uint8 constant internal REWARDS_PER_STAKING_LIMIT = 10;
//
//     function diamondStorage() internal pure returns (RewarderStorage storage s) {
//         bytes32 position = REWARDER_STORAGE_POSITION;
//         assembly {
//             s.slot := position
//         }
//     }
// }
