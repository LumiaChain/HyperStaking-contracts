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
    LibRewarder, RewarderStorage, UserRewardInfo, RewardInfo, RewardPool
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

    modifier onlyStopped(address strategy) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage info = r.rewardsInfo[strategy];

        require(info.stopped > 0, NotStopped());
        _;
    }

    modifier onlyNotStopped(address strategy) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage info = r.rewardsInfo[strategy];

        require(info.stopped == 0, Stopped());
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /**
     * Allows staker to receive a reward token.
     */
    function claim(address strategy, address user) external returns (uint256 pending) {
        updateUser(strategy, user);

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage info = r.rewardsInfo[strategy];
        UserRewardInfo storage userInfo = r.userInfo[strategy][user];

        pending = userInfo.rewardUnclaimed;

        if(pending > 0) {
            userInfo.rewardUnclaimed = 0;
            info.rewardToken.safeTransfer(user, pending);
            emit RewardClaim(strategy, user, pending);
        }
    }

    /**
     * @notice Function called by StrategyVault whenever withdrawal.
     * @dev updateUser depends on the totalStakeLocked (the value in effect until this moment).
     *      Function should be called before updating this value in the vault.
     * @param strategy address of strategy
     * @param user Address of the user
     */
    function updateUser(address strategy, address user) public nonReentrant {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        UserRewardInfo storage userInfo = r.userInfo[strategy][user];
        RewardPool storage pool = r.rewardPools[strategy];

        updatePool(strategy);

        userInfo.rewardUnclaimed = pendingReward(strategy, user);
        userInfo.rewardPerTokenPaid = pool.rewardPerToken;
    }

    /**
     * @notice Update reward pool storage for given strategy.
     */
    function updatePool(address strategy) public {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardPool storage pool = r.rewardPools[strategy];

        pool.rewardPerToken = _rewardPerToken(strategy);
        pool.lastRewardTimestamp = _lastTimeRewardApplicable(strategy);
    }

    /* ========== ACL  ========== */

    /**
     * @notice Function which transfrFrom reward tokens from the sender and starts updates
     *         reward distribution.
     * TODO ACL
     */
    function notifyReward(
        address strategy,
        IERC20 rewardToken,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd
    ) external onlyNotStopped(strategy) nonReentrant {
        require(address(rewardToken) != address(0), ZeroAddress());
        require(startTimestamp == 0 || startTimestamp >= block.timestamp, StartTimestampPassed());
        require(distributionEnd > startTimestamp, InvalidDistributionRange());

        updatePool(strategy);

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage info = r.rewardsInfo[strategy];
        RewardPool storage pool = r.rewardPools[strategy];

        require(
            address(info.rewardToken) == address(0) || info.rewardToken == rewardToken,
            "Bad Token"
        );

        if (startTimestamp == 0) {
            startTimestamp = uint64(block.timestamp);
        }

        // tokens left from an earlier unfinished distribution
        uint256 leftover = balance(strategy);

        // override previous distribution
        r.rewardsInfo[strategy] = RewardInfo({
            rewardToken: rewardToken,
            stopped: 0,
            distributionStart: startTimestamp,
            distributionEnd: distributionEnd
        });

        // precision is added to the rate to minimize the loss of precision when rounded down,
        // ensuring it doesn’t exceed the required value.
        require(rewardAmount + leftover <= 1e30, RateTooHigh());
        uint256 tokensPerSecond =
            (rewardAmount + leftover)
            * LibRewarder.REWARD_PRECISION
            / (distributionEnd - startTimestamp);

        pool.tokensPerSecond = tokensPerSecond;
        pool.lastRewardTimestamp = startTimestamp;

        rewardToken.safeTransferFrom(msg.sender, address(this), rewardAmount);

        emit RewardNotify(
            msg.sender,
            strategy,
            address(rewardToken),
            rewardAmount,
            leftover,
            startTimestamp,
            distributionEnd
        );
    }

    // TODO ACL
    function stop(address strategy) external {
        updatePool(strategy);

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage info = r.rewardsInfo[strategy];

        // determine the stop timestamp, defaulting to the current block timestamp
        // but capping it at the distribution end timestamp if the end has been reached
        uint64 stopped = uint64(block.timestamp);
        if (block.timestamp >= info.distributionEnd) {
            stopped = info.distributionEnd;
        }

        info.stopped = stopped;
        emit Stop(msg.sender, strategy, stopped);
    }

    /**
     * @notice Retrieves remaining reward tokens.
     * @dev only when rewarder is stopped.
     *
     * TODO ACL
     */
    function withdrawRemaining(
        address strategy,
        address receiver
    ) external onlyStopped(strategy) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage info = r.rewardsInfo[strategy];

        uint256 amount = balance(strategy);
        if(amount > 0) {
            info.rewardToken.safeTransfer(receiver, amount);
            emit WithdrawRemaining(msg.sender, strategy, receiver, amount);
        }
    }

    /* ========== VIEW ========== */

    /**
     * @notice View function to get balance of reward token.
     * @dev Balance refers to the amount of tokens that have not yet been distributed.
     */
    function balance(address strategy) public view returns (uint256) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage info = r.rewardsInfo[strategy];
        RewardPool storage pool = r.rewardPools[strategy];

        // timestamp to evaluate balance, set to the current block timestamp
        // or to the stop timestamp if distribution has stopped.
        uint64 evaluationTimestamp = uint64(block.timestamp);
        if (info.stopped != 0) {
            evaluationTimestamp = info.stopped;
        }

        if (evaluationTimestamp >= info.distributionEnd) {
            return 0;
        }

        uint64 remainingTime = info.distributionEnd - evaluationTimestamp;
        return remainingTime * pool.tokensPerSecond / LibRewarder.REWARD_PRECISION;
    }

    function rewarderExist(address strategy) public view returns (bool) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage info = r.rewardsInfo[strategy];

        if (address(info.rewardToken) == address(0)) {
            return false;
        }
        return true;
    }

    /**
     * @inheritdoc IRewarder
     */
    function pendingReward(address strategy, address user) public view returns (uint256) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        UserVaultInfo storage userVault = v.userInfo[strategy][user];

        RewarderStorage storage r = LibRewarder.diamondStorage();
        UserRewardInfo storage userInfo = r.userInfo[strategy][user];

        return
            userVault.stakeLocked
            * (_rewardPerToken(strategy) - userInfo.rewardPerTokenPaid)
            / LibRewarder.REWARD_PRECISION
            + userInfo.rewardUnclaimed;
    }

    function userRewardInfo(
        address strategy,
        address user
    ) external view returns (UserRewardInfo memory) {
        return LibRewarder.diamondStorage().userInfo[strategy][user];
    }

    function rewardInfo(address strategy) external view returns (RewardInfo memory) {
        return LibRewarder.diamondStorage().rewardsInfo[strategy];
    }

    function rewardPool(address strategy) external view returns (RewardPool memory) {
        return LibRewarder.diamondStorage().rewardPools[strategy];
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /**
     * @notice Returns current timestamp within token distribution or distribution end date
     */
    function _lastTimeRewardApplicable(address strategy) internal view returns (uint64) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage info = r.rewardsInfo[strategy];

        if (info.stopped > 0) {
            return info.stopped;
        }

        return uint64(block.timestamp) > info.distributionEnd
            ? info.distributionEnd : uint64(block.timestamp);
    }

    /**
     * @notice Fuction which calculate tokenReward based on current time state (timeElapsed)
     */
    function _tokenReward(address strategy) internal view returns (uint256) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardPool storage pool = r.rewardPools[strategy];

        uint64 timeElapsed = _lastTimeRewardApplicable(strategy) - pool.lastRewardTimestamp;
        return timeElapsed * pool.tokensPerSecond;
    }

    function _rewardPerToken(address strategy) internal view returns (uint256) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vaultInfo = v.vaultInfo[strategy];

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardPool storage pool = r.rewardPools[strategy];

        if (vaultInfo.totalStakeLocked == 0) {
            return pool.rewardPerToken;
        }

        return pool.rewardPerToken + _tokenReward(strategy) / vaultInfo.totalStakeLocked;
    }
}
