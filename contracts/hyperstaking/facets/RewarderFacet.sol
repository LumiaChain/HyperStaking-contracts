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
    LibRewarder, RewarderStorage, UserRewarderInfo, RewardInfo, RewardPool
} from "../libraries/LibRewarder.sol";

/**
 * @title RewarderFacet
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract RewarderFacet is IRewarder, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    modifier onlyStopped(address strategy_) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy_];

        require(rewardInfo.stopped > 0, NotStopped());
        _;
    }

    modifier onlyNotStopped(address strategy_) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy_];

        require(rewardInfo.stopped == 0, Stopped());
        _;
    }


    /**
     * @notice Function which transfrFrom reward tokens from the sender and starts updates
     *         reward distribution.
     * TODO ACL
     * TODO Pausable
     */
    function notifyReward(
        address strategy_,
        IERC20 rewardToken_,
        uint256 rewardAmount_,
        uint64 startTimestamp_,
        uint64 distributionEnd_
    ) external onlyNotStopped(strategy_) nonReentrant {
        require(address(rewardToken_) != address(0), ZeroAddress());
        require(startTimestamp_ >= block.timestamp, StartTimestampPassed());
        require(distributionEnd_ > startTimestamp_, InvalidDistributionRange());

        updatePool(strategy_);

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy_];
        RewardPool storage pool = r.rewardPools[strategy_];

        if (startTimestamp_ == 0) {
            startTimestamp_ = uint64(block.timestamp);
        }

        // tokens left from an earlier unfinished distribution
        uint256 leftover = _tokenReward(strategy_);

        // override previous distribution
        rewardInfo.rewardToken = rewardToken_;
        rewardInfo.distributionStart = startTimestamp_;
        rewardInfo.distributionEnd = distributionEnd_;

        // rate is rounded down (lose precision), so it should not exceed the available amount
        uint256 tokensPerSecond = (rewardAmount_ + leftover) / (distributionEnd_ - startTimestamp_);
        require(tokensPerSecond <= 1e30, RateTooHigh());

        pool.tokensPerSecond = tokensPerSecond;
        pool.lastRewardTimestamp = startTimestamp_;

        rewardToken_.safeTransferFrom(msg.sender, address(this), rewardAmount_ + leftover);

        emit RewardNotify(
            strategy_,
            address(rewardToken_),
            rewardAmount_,
            rewardAmount_ + leftover,
            startTimestamp_,
            distributionEnd_
        );
    }

    /**
     * @notice Retrieves remaining reward tokens.
     * @dev only when rewarder is stopped.
     * Emits {AdminWithdraw}.
     *
     * TODO ACL
     * TODO Pausable
     */
    function withdrawRemaining(
        address strategy_,
        address receiver_
    ) external onlyStopped(strategy_) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy_];

        uint256 amount = _tokenReward(strategy_);
        if(amount > 0) {
            rewardInfo.rewardToken.safeTransfer(receiver_, amount);
            emit WithdrawRemaining(strategy_, receiver_, amount);
        }
    }

    // /**
    //  * @notice Retrieves all reward tokens.
    //  * @dev should be used only in emergency.
    //  * Emits {AdminWithdraw}.
    //  *
    //  * TODO ACL
    //  * TODO consider if safe inside Diamond, so it couldn't withdraw tokens from other modules
    //  */
    // function emergencyWithdraw(address receiver_) external {
    //     RewarderStorage storage r = LibRewarder.diamondStorage();
    //
    //     uint256 amount = r.rewardToken.balanceOf(address(this));
    //     if(amount > 0) {
    //         r.ewardToken.safeTransfer(receiver_, amount);
    //         emit EnergencyWithdraw(receiver_, amount);
    //     }
    // }

    /* ========== DiamondInternal  ========== */

    /**
     * @notice Function called by StrategyVault whenever withdrawal.
     * @dev onUpdate depends on the totalStakeLocked (the value in effect until this moment).
     *      Function should be called before updating this value in the vault.
     * @param user_ Address of the user
     */
    function onUpdate(address strategy_, address user_) public nonReentrant {
        updatePool(strategy_);

        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        UserVaultInfo storage userVault = v.userInfo[strategy_][user_];

        RewarderStorage storage r = LibRewarder.diamondStorage();
        UserRewarderInfo storage userInfo = r.userInfo[strategy_][user_];
        RewardPool storage pool = r.rewardPools[strategy_];

        // include unclaimed tokens
        uint256 pending = _pendingTokens(strategy_, user_, pool);

        userInfo.amount = userVault.stakeLocked;
        userInfo.rewardPerTokenPaid =
            userInfo.amount * pool.accTokenPerShare
            / LibRewarder.REWARD_PRECISION;

        if (pending > 0) {
           userInfo.tokensUnclaimed += pending;
        }
    }

    // TODO ACL
    function stop(address strategy_) external {
        updatePool(strategy_);

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy_];

        uint64 stopped = uint64(block.timestamp);
        rewardInfo.stopped = stopped;
        emit Stop(strategy_, msg.sender, stopped);
    }

    /* ========== USER ========== */

    /**
     * Allows staker to receive a reward token.
     */
    function claim(address strategy_, address user_) external returns (uint256 pending) {
        onUpdate(strategy_, user_);

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy_];
        UserRewarderInfo storage userInfo = r.userInfo[strategy_][user_];

        pending = userInfo.tokensUnclaimed;
        if(pending > 0){
            userInfo.tokensUnclaimed = 0;
            rewardInfo.rewardToken.safeTransfer(user_, pending);
            emit RewardClaim(strategy_, user_, pending);
        }
    }

    /* ========== VIEW ========== */

    /**
     * @notice View function to see unclaimed tokens
     * @param user_ Address of user.
     * @return pending reward for a given user.
     */
    function unclaimedTokens(address strategy_, address user_) external view returns (uint256) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        UserRewarderInfo storage userInfo = r.userInfo[strategy_][user_];

        return  userInfo.tokensUnclaimed + _pendingTokens(strategy_, user_, _calculatePoolInfo(strategy_));
    }

    /**
     * @notice View function to see balance of reward token.
     * TODO It should not work like this
     */
    function balance(address strategy_) external view returns (uint256) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy_];

        return rewardInfo.rewardToken.balanceOf(address(this));
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /**
     * @notice Update reward variables of the given poolInfo.
     */
    function updatePool(address strategy_) public {
        RewardPool memory updatedPool = _calculatePoolInfo(strategy_);

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardPool storage pool = r.rewardPools[strategy_];

        if (updatedPool.lastRewardTimestamp > pool.lastRewardTimestamp) {
            r.rewardPools[strategy_] = pool;
        }
    }

    /**
     * @notice Returns current timestamp within token distribution or distribution end date
     */
    function _lastTimeRewardApplicable(address strategy_) internal view returns (uint64) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy_];

        if (rewardInfo.stopped > 0) {
            return rewardInfo.stopped;
        }

        return uint64(block.timestamp) > rewardInfo.distributionEnd
            ? rewardInfo.distributionEnd : uint64(block.timestamp);
    }

    /**
     * @notice Fuction which calculate tokenReward based on current time state (timeElapsed)
     */
    function _tokenReward(address strategy_) internal view returns (uint256) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardPool storage pool = r.rewardPools[strategy_];

        uint64 timeElapsed = _lastTimeRewardApplicable(strategy_) - pool.lastRewardTimestamp;
        return timeElapsed * pool.tokensPerSecond;
    }

    /**
     * @notice Helper function which calculates current pool info.
     * @dev Used for updating shares during pool update and for returning pendingTokens.
     */
    function _calculatePoolInfo(
        address strategy_
    ) internal view returns (RewardPool memory pool) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vaultInfo = v.vaultInfo[strategy_];

        RewarderStorage storage r = LibRewarder.diamondStorage();
        pool = r.rewardPools[strategy_];

        // reward distribution didn't started yet
        if (pool.lastRewardTimestamp == 0) {
            return pool;
        }

        uint256 tokenReward = _tokenReward(strategy_);
        if (tokenReward > 0) {
            if (vaultInfo.totalStakeLocked > 0) {
                // increase acctokenPerShare
                pool.accTokenPerShare +=
                    tokenReward * LibRewarder.REWARD_PRECISION
                    / vaultInfo.totalStakeLocked;
            }

            // update timestamp
            pool.lastRewardTimestamp = _lastTimeRewardApplicable(strategy_);
        }
    }

    /**
     * @notice Internal function for pendingTokens.
     * @return pending reward for a given user.
     */
    function _pendingTokens(
        address strategy_,
        address user_,
        RewardPool memory pool_
    ) internal view returns (uint256 pending) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        UserRewarderInfo storage userInfo = r.userInfo[strategy_][user_];

        pending =
            userInfo.amount * pool_.accTokenPerShare / LibRewarder.REWARD_PRECISION
            - userInfo.rewardPerTokenPaid;
    }
}
