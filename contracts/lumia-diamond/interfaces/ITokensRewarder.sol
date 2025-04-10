// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UserRewardInfo, RewardPool} from "../libraries/LibRewards.sol";

/**
 * @title ITokensRewarder
 * @notice Interface for managing the distribution of multiple reward tokens to stakers via MasterChef
 */
interface ITokensRewarder {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event TokensRewarderSetup(
        address diamond,
        address stakeToken
    );

    event RewardNotify(
        address indexed sender,
        address indexed rewardToken,
        uint256 indexed idx,
        uint256 rewardAmount,
        uint256 leftover,
        uint64 startTimestamp,
        uint64 endTimestamp,
        bool newReward
    );

    event RewardClaim(address indexed rewardToken, uint256 idx, address indexed user, uint256 amount);

    event WithdrawRemaining(
        address indexed sender,
        address indexed rewardToken,
        uint256 idx,
        address receiver,
        uint256 amount
    );
    event Finalize(address sender, address rewardToken, uint256 idx, uint64 finalizeTimestamp);

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error ZeroDiamond();
    error ZeroStakeToken();

    error NotLumiaDiamond();
    error NotLumiaRewardManager();

    error TokenZeroAddress();
    error NoActiveRewardFound();
    error ActiveRewardsLimitReached();

    error Finalized();
    error NotFinalized();

    error RewardNotFound();
    error RateTooHigh();
    error StartTimestampPassed();
    error InvalidDistributionRange();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Allows the staker to claim all available rewards associated with this rewarder
     */
    function claimAll(address user) external;

    /**
     * @notice Allows the staker to claim a specific reward, identified by its index
     * @return pending Amount of tokens that were claimed
     */
    function claimReward(uint256 idx, address user) external returns (uint256 pending);

    /**
     * @notice Main update function called by MasterChef to refresh both pool and user states
     * @dev If `user` is the zero address, only the pool state is updated (no user-specific update)
     */
    function updateActivePools(address user) external;

    /**
     * @notice Updates the user's state based on the stake locked in MasterChef
     * @dev This function should be called after changing the stake value
     */
    function updateUser(uint256 idx, address user) external;

    /**
     * @notice Updates the reward pool's
     */
    function updatePool(uint256 idx) external;

    /* ========== ACL  ========== */

    /**
     * @notice Initiates a new reward distribution for a given stake token
     * @return idx The index assigned to the newly created reward pool
     */
    function newRewardDistribution(
        IERC20 rewardToken,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd
    ) external returns (uint256 idx);

    /**
     * @notice Notifies an existing reward pool of new distribution parameters and top-up amount
     *         This function transfers additional reward tokens from the caller
     */
    function notifyRewardDistribution(
        uint256 idx,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd
    ) external;

    /**
     * @notice Finalizes all active reward distributions
     */
    function finalizeAll() external;

    /**
     * @notice Finalizes a reward distribution
     */
    function finalize(uint256 idx) external;

    /**
     * @notice Retrieves any remaining (undistributed) reward tokens once the reward pool is finalized
     */
    function withdrawRemaining(uint256 idx, address receiver) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /**
     * @notice Returns the core information for a reward distribution
     */
    function rewardInfo(uint256 idx)
        external
        view
        returns (IERC20 rewardToken, uint64 finalizeTimestamp);

    /**
     * @notice Returns the reward information specific to a user's position
     */
    function userRewardInfo(uint256 idx, address user) external view returns (UserRewardInfo memory);

    /**
     * @notice Returns the full configuration for the reward pool at a given index
     */
    function rewardPool(uint256 idx) external view returns (RewardPool memory);

    /**
     * @notice Lists the indexes of all currently active rewards
     */
    function getActiveRewardList() external view returns (uint256[] memory idxList);

    /**
     * @notice Checks whether all active rewards have been finalized (i.e., no active pools remain)
     * @dev Returns `true` if `activeRewardList` is empty, indicating there are no ongoing distributions
     */
    function finalizedAll() external view returns (bool);

    /**
     * @notice Indicates if a particular reward distribution has been finalized
     */
    function finalized(uint256 idx) external view returns (bool);

    /**
     * @notice Checks whether the reward distribution at `idx` is active
     */
    function isRewardActive(uint256 idx) external view returns (bool);

    /**
     * @notice Retrieves the total amount of reward tokens that have not yet been distributed
     */
    function balance(uint256 idx) external view returns (uint256);

    /**
     * @notice Calculates the unclaimed (pending) reward for a specific user in a given reward pool
     * @return Pending reward amount for the user
     */
    function pendingReward(
        uint256 idx,
        address user
    ) external view returns (uint256);

    /* ========== Constans  ========== */

    // solhint-disable-next-line func-name-mixedcase
    function REWARD_PRECISION() external view returns (uint256);

    // solhint-disable-next-line func-name-mixedcase
    function REWARDS_PER_STAKING_LIMIT() external view returns (uint8);
}
