// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ITokensRewarder} from "./interfaces/ITokensRewarder.sol";
import {IMasterChef} from "./interfaces/IMasterChef.sol";
import {LumiaDiamondAcl} from "./LumiaDiamondAcl.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {UserRewardInfo, RewardPool, RewardDistribution} from "./libraries/LibRewards.sol";

/**
 * @title TokensRewarder
 * @notice Manages the distribution of multiple reward tokens to stakers via MasterChef
 */
contract TokensRewarder is ITokensRewarder, LumiaDiamondAcl, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    //============================================================================================//
    //                                          Storage                                           //
    //============================================================================================//

    // Considers edge cases for token reward calculation: preventing overflow with max values
    // and avoiding rounding to zero with minimal values. This precision value is a solid compromise
    uint256 constant public REWARD_PRECISION = 1e36;

    // Maximum number of concurrent rewards allowed
    uint8 constant public REWARDS_PER_STAKING_LIMIT = 10;

    // @notice Address (immutable) of the lumia diamond contract
    address public immutable DIAMOND;

    // @notice Address of the stake token used in this rewarder
    address public stakeToken;

    /// @notice Tracks the current reward index, starting from 0 by default
    /// @dev This index reflects the total number of rewards created by this rewarder
    ///      It increments each time a new reward is added for a token
    uint256 public rewardTokenIndex;

    /// @notice An array of reward distributions
    mapping(uint256 idx => RewardDistribution) public rewardDistributions;

    /// @notice List of active reward IDs
    /// @dev Should not exceed the defined limit of rewards (REWARDS_PER_STAKE_LIMIT)
    uint256[] public activeRewardList;

    /// @notice Optimized mapping for cheap access to active rewards
    /// @dev Maps reward idx to a boolean indicating whether the reward is active
    mapping(uint256 idx => bool) public activeRewards;

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    modifier onlyLumiaDiamond() {
        require(msg.sender == DIAMOND, NotLumiaDiamond());
        _;
    }

    /// @notice Use LumiaDiamondAcl Helper to check to Lumia Reward Manager
    modifier onlyLumiaManager() {
        require(
            LumiaDiamondAcl(DIAMOND).hasLumiaRewardManagerRole(msg.sender),
            NotLumiaRewardManager()
        );
        _;
    }

    modifier onlyFinalized(uint256 idx) {
        require(finalized(idx), NotFinalized());
        _;
    }

    modifier onlyNotFinalized(uint256 idx) {
        RewardDistribution storage reward = _getRewardDistribution(idx);
        require(!finalized(idx), Finalized());
        _;
    }

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    /**
     * @notice Initializes the contract with the provided diamond and stake token addresses
     * @dev Diamond is immutable. Zero addresses are disallowed
     * @param diamond_ Address of the diamond contract
     * @param stakeToken_ Address of the stake token
     */
    constructor(address diamond_, address stakeToken_) {
        if (diamond_ == address(0)) revert ZeroDiamond();
        if (stakeToken_ == address(0)) revert ZeroStakeToken();

        DIAMOND = diamond_;
        stakeToken = stakeToken_;

        emit TokensRewarderSetup(diamond_, stakeToken_);
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc ITokensRewarder
    function claimAll(address user) external nonReentrant {
        uint256[] memory idxList = activeRewardList;
        uint256 length = idxList.length;

        // loop is limited with REWARDS_PER_STAKING_LIMIT
        for (uint256 i = 0; i < length; i++) {
            _claimReward(idxList[i], user);
        }
    }

    /// @inheritdoc ITokensRewarder
    function claimReward(
        uint256 idx,
        address user
    ) external nonReentrant returns (uint256 pending) {
        pending = _claimReward(idx, user);
    }

    /// @inheritdoc ITokensRewarder
    function updateActivePools(address user) public nonReentrant {
        _updateActivePools(user);
    }

    /// @inheritdoc ITokensRewarder
    function updateUser(uint256 idx, address user) public nonReentrant {
        _updateUser(idx, user);
    }

    /// @inheritdoc ITokensRewarder
    function updatePool(uint256 idx) public nonReentrant {
        _updatePool(idx);
    }

    /* ========== ACL  ========== */

    /// @inheritdoc ITokensRewarder
    function newRewardDistribution(
        IERC20 rewardToken,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd
    ) external onlyLumiaManager nonReentrant returns (uint256 idx) {
        require(address(rewardToken) != address(0), TokenZeroAddress());

        idx = _newIdx();

        // set rewardToken address
        RewardDistribution storage reward = _getRewardDistribution(idx);
        reward.rewardToken = rewardToken;

        _notifyReward(idx, rewardAmount, startTimestamp, distributionEnd, true);
    }

    /// @inheritdoc ITokensRewarder
    function notifyRewardDistribution(
        uint256 idx,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd
    ) external onlyLumiaManager onlyNotFinalized(idx) nonReentrant {
        require(isRewardActive(idx) == true, NoActiveRewardFound());

        _notifyReward(idx, rewardAmount, startTimestamp, distributionEnd, false);
    }

    /// @inheritdoc ITokensRewarder
    function finalizeAll() external onlyLumiaManager nonReentrant {
        uint256[] memory idxList = activeRewardList;

        for (uint256 i = 0; i < idxList.length; i++) {
            _finalize(idxList[i]);
        }
    }

    /// @inheritdoc ITokensRewarder
    function finalize(
        uint256 idx
    ) external onlyLumiaManager nonReentrant {
        _finalize(idx);
    }

    /// @inheritdoc ITokensRewarder
    function withdrawRemaining(
        uint256 idx,
        address receiver
    ) external onlyLumiaManager onlyFinalized(idx) {
        RewardDistribution storage reward = _getRewardDistribution(idx);

        uint256 amount = balance(idx);
        if(amount > 0) {
            reward.rewardToken.safeTransfer(receiver, amount);
            emit WithdrawRemaining(msg.sender, address(reward.rewardToken), idx, receiver, amount);
        }
    }

    /* ========== View ========== */

    /// @inheritdoc ITokensRewarder
    function rewardInfo(uint256 idx)
        external
        view
        returns (IERC20 rewardToken, uint64 finalizeTimestamp)
    {
        RewardDistribution storage reward = _getRewardDistribution(idx);

        rewardToken = reward.rewardToken;
        finalizeTimestamp = reward.finalizeTimestamp;
    }

    /// @inheritdoc ITokensRewarder
    function userRewardInfo(uint256 idx, address user) external view returns (UserRewardInfo memory) {
        RewardDistribution storage reward = _getRewardDistribution(idx);
        return reward.users[user];
    }

    /// @inheritdoc ITokensRewarder
    function rewardPool(uint256 idx) external view returns (RewardPool memory) {
        RewardDistribution storage reward = _getRewardDistribution(idx);
        return reward.pool;
    }

    /// @inheritdoc ITokensRewarder
    function finalizedAll() external view returns (bool) {
        return activeRewardList.length == 0;
    }

    /// @inheritdoc ITokensRewarder
    function getActiveRewardList() external view returns (uint256[] memory idxList) {
        idxList = activeRewardList;
    }

    /// @inheritdoc ITokensRewarder
    function finalized(uint256 idx) public view returns (bool) {
        RewardDistribution storage reward = _getRewardDistribution(idx);
        return reward.finalizeTimestamp > 0;
    }

    /// @inheritdoc ITokensRewarder
    function isRewardActive(uint256 idx) public view returns (bool) {
        return activeRewards[idx];
    }

    /// @inheritdoc ITokensRewarder
    function balance(uint256 idx) public view returns (uint256) {
        RewardDistribution storage reward = _getRewardDistribution(idx);

        // timestamp to evaluate balance, set to the current block timestamp
        // or to the finalize timestamp if distribution has finalize
        uint64 evaluationTimestamp = uint64(block.timestamp);
        if (reward.finalizeTimestamp > 0) {
            evaluationTimestamp = reward.finalizeTimestamp;
        }

        if (evaluationTimestamp >= reward.pool.distributionEnd) {
            return 0;
        }

        uint64 remainingTime = reward.pool.distributionEnd - evaluationTimestamp;
        return remainingTime * reward.pool.tokensPerSecond / REWARD_PRECISION;
    }

    /// @inheritdoc ITokensRewarder
    function pendingReward(
        uint256 idx,
        address user
    ) public view returns (uint256) {
        RewardDistribution storage reward = _getRewardDistribution(idx);
        UserRewardInfo storage userInfo = reward.users[user];

        // Use MasterChef (Lumia Diamond facet) to get current stake vaule
        uint256 userStakeAmount = IMasterChef(DIAMOND).getUserStake(stakeToken, user);

        return
            userStakeAmount
            * (_rewardPerToken(idx) - userInfo.rewardPerTokenPaid)
            / REWARD_PRECISION
            + userInfo.rewardUnclaimed;
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Generates a new reward index, enforces the limit
    function _newIdx() internal returns (uint256 idx) {
        require(
            activeRewardList.length < REWARDS_PER_STAKING_LIMIT,
            ActiveRewardsLimitReached()
        );

        idx = rewardTokenIndex;
        rewardTokenIndex++; // increment index

        activeRewardList.push(idx);
        activeRewards[idx] = true;
    }

    /// @notice Internal logic for claiming a reward, called by claimReward to apply nonReentrant
    function _claimReward(
        uint256 idx,
        address user
    ) internal returns (uint256 pending) {
        _updatePool(idx);
        _updateUser(idx, user);

        RewardDistribution storage reward = _getRewardDistribution(idx);
        UserRewardInfo storage userInfo = reward.users[user];

        pending = userInfo.rewardUnclaimed;

        if(pending > 0) {
            userInfo.rewardUnclaimed = 0;
            reward.rewardToken.safeTransfer(user, pending);
            emit RewardClaim(address(reward.rewardToken), idx, user, pending);
        }
    }

    /// @notice Internal logic for updating user and pool data, called by other functions
    function _updateActivePools(address user) internal {
        uint256[] memory idxList = activeRewardList;

        // loops are limited with REWARDS_PER_STAKING_LIMIT
        for (uint256 i = 0; i < idxList.length; i++) {
            _updatePool(idxList[i]);
        }

        if (user != address(0)) {
            for (uint256 i = 0; i < idxList.length; i++) {
                _updateUser(idxList[i], user);
            }
        }
    }

    /// @notice Internal logic for updating user data, called by other functions
    function _updateUser(uint256 idx, address user) internal {
        RewardDistribution storage reward = _getRewardDistribution(idx);
        UserRewardInfo storage userInfo = reward.users[user];

        userInfo.rewardUnclaimed = pendingReward(idx, user);
        userInfo.rewardPerTokenPaid = reward.pool.rewardPerToken;
    }

    /// @notice Internal logic for updating pool data, called by other functions
    function _updatePool(uint256 idx) internal {
        RewardDistribution storage reward = _getRewardDistribution(idx);

        reward.pool.rewardPerToken = _rewardPerToken(idx);
        reward.pool.lastRewardTimestamp = _lastTimeRewardApplicable(idx);
    }

    /// @notice Notifies or creates a new reward distribution, transferring tokens and setting parameters
    function _notifyReward(
        uint256 idx,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd,
        bool newReward
    ) internal {
        require(startTimestamp == 0 || startTimestamp >= block.timestamp, StartTimestampPassed());
        require(distributionEnd > startTimestamp, InvalidDistributionRange());

        _updateActivePools(address(0));

        RewardDistribution storage reward = _getRewardDistribution(idx);

        if (startTimestamp == 0) {
            startTimestamp = uint64(block.timestamp);
        }

        uint256 leftover = 0;
        if (!newReward) {
            // tokens left from an earlier unfinished distribution
            leftover = balance(idx);
        }

        // override previous distribution
        reward.pool.distributionStart = startTimestamp;
        reward.pool.distributionEnd = distributionEnd;

        // precision is added to the rate to minimize the loss of precision when rounded down,
        // ensuring it doesn’t exceed the required value
        require(rewardAmount + leftover <= 1e30, RateTooHigh());
        uint256 tokensPerSecond =
            (rewardAmount + leftover)
            * REWARD_PRECISION
            / (distributionEnd - startTimestamp);

        reward.pool.tokensPerSecond = tokensPerSecond;
        reward.pool.lastRewardTimestamp = startTimestamp;

        reward.rewardToken.safeTransferFrom(msg.sender, address(this), rewardAmount);

        emit RewardNotify(
            msg.sender,
            address(reward.rewardToken),
            idx,
            rewardAmount,
            leftover,
            startTimestamp,
            distributionEnd,
            newReward
        );
    }

    /// @notice Internal logic for finalizing reward distribution, called by other functions
    function _finalize(uint256 idx) internal onlyNotFinalized(idx) {
        _updatePool(idx);

        RewardDistribution storage reward = _getRewardDistribution(idx);

        // determine the finalize timestamp, defaulting to the current block timestamp
        // but capping it at the distribution end timestamp if the end has been reached
        uint64 finalizeTimestamp = uint64(block.timestamp);

        if (block.timestamp >= reward.pool.distributionEnd) {
            finalizeTimestamp = reward.pool.distributionEnd;
        } else {
            finalizeTimestamp = uint64(block.timestamp);
        }

        _deactivateReward(idx);
        reward.finalizeTimestamp = finalizeTimestamp;

        emit Finalize(msg.sender, address(reward.rewardToken), idx, finalizeTimestamp);
    }

    /// @notice Removes a reward distribution from the active list and deactivates it
    function _deactivateReward(uint256 idx) internal {
        uint256[] storage idxList = activeRewardList;
        uint256 length = idxList.length;

        // find the index and remove it
        for (uint256 i = 0; i < length; i++) {
            if (idxList[i] == idx) {
                // Shift elements to the left to remove the index
                for (uint256 j = i; j < length - 1; j++) {
                    idxList[j] = idxList[j + 1];
                }
                idxList.pop(); // Remove the last element
                break;
            }
        }

        activeRewards[idx] = false;
    }

    /* ========== View ========== */

    /// @notice Retrieves the stored RewardDistribution for the specified index
    function _getRewardDistribution(
        uint256 idx
    ) internal view returns (RewardDistribution storage) {
        require(rewardTokenIndex > idx, RewardNotFound());
        return rewardDistributions[idx];
    }

    /// @notice Returns the last applicable timestamp for a given reward
    function _lastTimeRewardApplicable(uint256 idx) internal view returns (uint64) {
        RewardDistribution storage reward = _getRewardDistribution(idx);

        if (reward.finalizeTimestamp > 0) {
            return reward.finalizeTimestamp;
        }

        uint64 timeNow = uint64(block.timestamp);

        // distribution didn't starter yet
        if (timeNow < reward.pool.distributionStart) {
            return reward.pool.distributionStart;
        }

        // distribution is already finished
        if (timeNow > reward.pool.distributionEnd) {
            return reward.pool.distributionEnd;
        }

        return timeNow;
    }

    /// @notice Calculates the total reward tokens generated since the last reward timestamp
    function _tokenReward(uint256 idx) internal view returns (uint256) {
        RewardDistribution storage reward = _getRewardDistribution(idx);
        RewardPool storage pool = reward.pool;

        uint64 timeElapsed = _lastTimeRewardApplicable(idx) - pool.lastRewardTimestamp;
        return timeElapsed * pool.tokensPerSecond;
    }


    /// @notice Computes the reward per token
    function _rewardPerToken(uint256 idx) internal view returns (uint256) {
        RewardDistribution storage reward = _getRewardDistribution(idx);
        RewardPool storage pool = reward.pool;

        uint256 totalStaked = IMasterChef(DIAMOND).getTotalStake(stakeToken);
        if (totalStaked == 0) {
            return pool.rewardPerToken;
        }

        return pool.rewardPerToken + _tokenReward(idx) / totalStaked;
    }
}
