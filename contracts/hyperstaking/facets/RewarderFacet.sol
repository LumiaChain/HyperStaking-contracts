// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IRewarder} from "../interfaces/IRewarder.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    LibStrategyVault, StrategyVaultStorage, UserVaultInfo, VaultInfo
} from "../libraries/LibStrategyVault.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {
    LibRewarder, RewarderStorage, StrategyReward, UserRewardInfo, RewardPool
} from "../libraries/LibRewarder.sol";

/**
 * @title RewarderFacet
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract RewarderFacet is IRewarder, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    modifier onlyStopped(address strategy, uint256 idx) {
        StrategyReward storage reward = _getStrategyReward(strategy, idx);
        require(reward.stopped > 0, NotStopped());
        _;
    }

    modifier onlyNotStopped(address strategy, uint256 idx) {
        StrategyReward storage reward = _getStrategyReward(strategy, idx);
        require(reward.stopped == 0, Stopped());
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /**
     * Allows staker to receive a reward token.
     */
    function claimAll(address strategy, address user) external nonReentrant {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        uint256[] memory idxList =  r.activeRewardLists[strategy];
        uint256 length =  idxList.length;

        // loop is limited with REWARDS_PER_STRATEGY_LIMIT

        for (uint256 i = 0; i < length; i++) {
            _claimReward(strategy, idxList[i], user);
        }
    }

    function claimReward(
        address strategy,
        uint256 idx,
        address user
    ) external nonReentrant returns (uint256 pending) {
        pending = _claimReward(strategy, idx, user);
    }

    /**
     * @notice Update userInfo for all active rewards on given strategy.
     * @notice Update all active strategy rewards distribution.
     * @dev user == AddressZero - update only pools
     */
    function updateActivePools(address strategy, address user) public {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        uint256[] memory idxList =  r.activeRewardLists[strategy];
        // uint256 length = rewards.length; // check gas!
        // uint256 length =  r.activeRewardLists[strategy].length;

        // loops are limited with REWARDS_PER_STRATEGY_LIMIT

        for (uint256 i = 0; i < idxList.length; i++) {
            updatePool(strategy, idxList[i]);
        }

        if (user != address(0)) {
            for (uint256 i = 0; i < idxList.length; i++) {
                updateUser(strategy, idxList[i], user);
            }
        }
    }

    /**
     * @notice Function called by StrategyVault whenever withdrawal.
     * @dev updateUser depends on the totalStakeLocked (the value in effect until this moment).
     *      Function should be called before updating this value in the vault.
     * @param strategy address of strategy
     * @param user Address of the user
     */
    function updateUser(address strategy, uint256 idx, address user) public {
        StrategyReward storage reward = _getStrategyReward(strategy, idx);
        UserRewardInfo storage userInfo = reward.users[user];

        userInfo.rewardUnclaimed = pendingReward(strategy, idx, user);
        userInfo.rewardPerTokenPaid = reward.pool.rewardPerToken;
    }

    /**
     * @notice Update reward pool storage for given strategy.
     */
    function updatePool(address strategy, uint256 idx) public {
        StrategyReward storage reward = _getStrategyReward(strategy, idx);

        reward.pool.rewardPerToken = _rewardPerToken(strategy, idx);
        reward.pool.lastRewardTimestamp = _lastTimeRewardApplicable(strategy, idx);
    }

    /* ========== ACL  ========== */

    /**
     * TODO ACL
     */
    function newRewardDistribution(
        address strategy,
        IERC20 rewardToken,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd
    ) external nonReentrant returns (uint256 idx) {
        require(address(rewardToken) != address(0), TokenZeroAddress());

        idx = _newIdx(strategy);

        // set rewardToken address
        StrategyReward storage reward = _getStrategyReward(strategy, idx);
        reward.rewardToken = rewardToken;

        _notifyReward(strategy, idx, rewardAmount, startTimestamp, distributionEnd, true);
    }

    /**
     * @notice Function which transfrFrom reward tokens from the sender and starts updates
     *         reward distribution.
     * TODO ACL
     */
    function notifyRewardDistribution(
        address strategy,
        uint256 idx,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd
    ) external onlyNotStopped(strategy, idx) nonReentrant {
        require(isRewardActive(strategy, idx) == true, NoActiveRewardFound());

        _notifyReward(strategy, idx, rewardAmount, startTimestamp, distributionEnd, false);
    }

    // TODO ACL
    function stop(address strategy, uint256 idx) external onlyNotStopped(strategy, idx) {
        updatePool(strategy, idx);

        StrategyReward storage reward = _getStrategyReward(strategy, idx);

        // determine the stop timestamp, defaulting to the current block timestamp
        // but capping it at the distribution end timestamp if the end has been reached
        uint64 stopped = uint64(block.timestamp);
        if (block.timestamp >= reward.pool.distributionEnd) {
            stopped = reward.pool.distributionEnd;
        }

        _deactivateReward(strategy, idx);
        reward.stopped = stopped;

        emit Stop(msg.sender, strategy, idx, stopped);
    }

    /**
     * @notice Retrieves remaining reward tokens.
     * @dev only when rewarder is stopped.
     *
     * TODO ACL
     */
    function withdrawRemaining(
        address strategy,
        uint256 idx,
        address receiver
    ) external onlyStopped(strategy, idx) {
        StrategyReward storage reward = _getStrategyReward(strategy, idx);

        uint256 amount = balance(strategy, idx);
        if(amount > 0) {
            reward.rewardToken.safeTransfer(receiver, amount);
            emit WithdrawRemaining(msg.sender, strategy, idx, receiver, amount);
        }
    }

    /* ========== VIEW ========== */

    /**
     * @notice View function to get balance of reward token.
     * @dev Balance refers to the amount of tokens that have not yet been distributed.
     */
    function balance(address strategy, uint256 idx) public view returns (uint256) {
        StrategyReward storage reward = _getStrategyReward(strategy, idx);

        // timestamp to evaluate balance, set to the current block timestamp
        // or to the stop timestamp if distribution has stopped.
        uint64 evaluationTimestamp = uint64(block.timestamp);
        if (reward.stopped != 0) {
            evaluationTimestamp = reward.stopped;
        }

        if (evaluationTimestamp >= reward.pool.distributionEnd) {
            return 0;
        }

        uint64 remainingTime = reward.pool.distributionEnd - evaluationTimestamp;
        return remainingTime * reward.pool.tokensPerSecond / LibRewarder.REWARD_PRECISION;
    }

    /**
     * @inheritdoc IRewarder
     */
    function pendingReward(
        address strategy,
        uint256 idx,
        address user
    ) public view returns (uint256) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        UserVaultInfo storage userVault = v.userInfo[strategy][user];

        StrategyReward storage reward = _getStrategyReward(strategy, idx);
        UserRewardInfo storage userInfo = reward.users[user];

        return
            userVault.stakeLocked
            * (_rewardPerToken(strategy, idx) - userInfo.rewardPerTokenPaid)
            / LibRewarder.REWARD_PRECISION
            + userInfo.rewardUnclaimed;
    }

    function strategyIndex(address strategy) external view returns (uint256) {
        return LibRewarder.diamondStorage().strategyIndex[strategy];
    }

    function isRewardActive(address strategy, uint256 idx) public view returns (bool) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        return r.activeRewards[strategy][idx];
    }

    function activeRewardList(address strategy) public view returns (uint256[] memory idxList) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        idxList = r.activeRewardLists[strategy];
    }

    function strategyRewardInfo(
        address strategy,
        uint256 idx
    ) external view returns (IERC20 rewardToken, uint64 stopped) {
        StrategyReward storage reward = _getStrategyReward(strategy, idx);

        rewardToken = reward.rewardToken;
        stopped = reward.stopped;
    }

    function userRewardInfo(
        address strategy,
        uint256 idx,
        address user
    ) external view returns (UserRewardInfo memory) {
        StrategyReward storage reward = _getStrategyReward(strategy, idx);
        return reward.users[user];
    }

    function rewardPool(address strategy, uint256 idx) external view returns (RewardPool memory) {
        StrategyReward storage reward = _getStrategyReward(strategy, idx);
        return reward.pool;
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    function _newIdx(address strategy) internal returns (uint256 idx) {
        RewarderStorage storage r = LibRewarder.diamondStorage();

        require(
            r.activeRewardLists[strategy].length < LibRewarder.REWARDS_PER_STRATEGY_LIMIT,
            ActiveRewardsLimitReached()
        );

        idx = r.strategyIndex[strategy];
        r.strategyIndex[strategy]++; // increment strategy index

        r.activeRewardLists[strategy].push(idx);
        r.activeRewards[strategy][idx] = true;
    }

    function _getStrategyReward(
        address strategy,
        uint256 idx
    ) internal view returns (StrategyReward storage) {
        RewarderStorage storage r = LibRewarder.diamondStorage();

        require(r.strategyIndex[strategy] > idx, RewardNotFound());

        return r.strategyRewards[strategy][idx];
    }

    // separated claimReward logic into internal function so it could apply nonReentrant
    function _claimReward(
        address strategy,
        uint256 idx,
        address user
    ) internal returns (uint256 pending) {
        updatePool(strategy, idx);
        updateUser(strategy, idx, user);

        StrategyReward storage reward = _getStrategyReward(strategy, idx);
        UserRewardInfo storage userInfo = reward.users[user];

        pending = userInfo.rewardUnclaimed;

        if(pending > 0) {
            userInfo.rewardUnclaimed = 0;
            reward.rewardToken.safeTransfer(user, pending);
            emit RewardClaim(strategy, idx, user, pending);
        }
    }

    function _notifyReward(
        address strategy,
        uint256 idx,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd,
        bool newReward
    ) internal {
        require(startTimestamp == 0 || startTimestamp >= block.timestamp, StartTimestampPassed());
        require(distributionEnd > startTimestamp, InvalidDistributionRange());

        updateActivePools(strategy, address(0));

        StrategyReward storage reward = _getStrategyReward(strategy, idx);

        if (startTimestamp == 0) {
            startTimestamp = uint64(block.timestamp);
        }

        uint256 leftover = 0;
        if (!newReward) {
            // tokens left from an earlier unfinished distribution
            leftover = balance(strategy, idx);
        }

        // override previous distribution
        reward.pool.distributionStart = startTimestamp;
        reward.pool.distributionEnd = distributionEnd;

        // precision is added to the rate to minimize the loss of precision when rounded down,
        // ensuring it doesn’t exceed the required value.
        require(rewardAmount + leftover <= 1e30, RateTooHigh());
        uint256 tokensPerSecond =
            (rewardAmount + leftover)
            * LibRewarder.REWARD_PRECISION
            / (distributionEnd - startTimestamp);

        reward.pool.tokensPerSecond = tokensPerSecond;
        reward.pool.lastRewardTimestamp = startTimestamp;

        reward.rewardToken.safeTransferFrom(msg.sender, address(this), rewardAmount);

        emit RewardNotify(
            msg.sender,
            strategy,
            idx,
            rewardAmount,
            leftover,
            startTimestamp,
            distributionEnd,
            newReward
        );
    }

    /**
     * @notice Returns current timestamp within token distribution or distribution end date
     */
    function _lastTimeRewardApplicable(address strategy, uint256 idx) internal view returns (uint64) {
        StrategyReward storage reward = _getStrategyReward(strategy, idx);

        if (reward.stopped > 0) {
            return reward.stopped;
        }

        return uint64(block.timestamp) > reward.pool.distributionEnd
            ? reward.pool.distributionEnd : uint64(block.timestamp);
    }

    /**
     * @notice Fuction which calculate tokenReward based on current time state (timeElapsed)
     */
    function _tokenReward(address strategy, uint256 idx) internal view returns (uint256) {
        StrategyReward storage reward = _getStrategyReward(strategy, idx);
        RewardPool storage pool = reward.pool;

        uint64 timeElapsed = _lastTimeRewardApplicable(strategy, idx) - pool.lastRewardTimestamp;
        return timeElapsed * pool.tokensPerSecond;
    }

    function _rewardPerToken(address strategy, uint256 idx) internal view returns (uint256) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vaultInfo = v.vaultInfo[strategy];

        StrategyReward storage reward = _getStrategyReward(strategy, idx);
        RewardPool storage pool = reward.pool;

        if (vaultInfo.totalStakeLocked == 0) {
            return pool.rewardPerToken;
        }

        return pool.rewardPerToken + _tokenReward(strategy, idx) / vaultInfo.totalStakeLocked;
    }

    function _deactivateReward(address strategy, uint256 idx) internal {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        uint256[] storage idxList =  r.activeRewardLists[strategy];
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

        r.activeRewards[strategy][idx] = false;
    }
}
