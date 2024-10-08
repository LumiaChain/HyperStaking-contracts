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
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy];

        require(rewardInfo.stopped > 0, NotStopped());
        _;
    }

    modifier onlyNotStopped(address strategy) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy];

        require(rewardInfo.stopped == 0, Stopped());
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /**
     * Allows staker to receive a reward token.
     */
    function claim(address strategy, address user) external returns (uint256 pending) {
        onUpdate(strategy, user);

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy];
        UserRewardInfo storage userInfo = r.userInfo[strategy][user];

        pending = userInfo.tokensUnclaimed;
        if(pending > 0){
            userInfo.tokensUnclaimed = 0;
            rewardInfo.rewardToken.safeTransfer(user, pending);
            emit RewardClaim(strategy, user, pending);
        }
    }

    /**
     * @notice Function called by StrategyVault whenever withdrawal.
     * @dev onUpdate depends on the totalStakeLocked (the value in effect until this moment).
     *      Function should be called before updating this value in the vault.
     * @param strategy address of strategy
     * @param user Address of the user
     */
    function onUpdate(address strategy, address user) public nonReentrant {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        UserVaultInfo storage userVault = v.userInfo[strategy][user];

        RewarderStorage storage r = LibRewarder.diamondStorage();
        UserRewardInfo storage userInfo = r.userInfo[strategy][user];
        RewardPool storage pool = r.rewardPools[strategy];
        updatePool(strategy);

        // include unclaimed tokens
        uint256 pending = _pendingTokens(strategy, user, pool);

        userInfo.amount = userVault.stakeLocked;
        userInfo.rewardPerTokenPaid =
            userInfo.amount * pool.accTokenPerShare
            / LibRewarder.REWARD_PRECISION;

        if (pending > 0) {
           userInfo.tokensUnclaimed += pending;
        }
    }

    /**
     * @notice Update reward variables of the given poolInfo.
     */
    function updatePool(address strategy) public {
        RewardPool memory updatedPool = _calculatePoolInfo(strategy);

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardPool storage pool = r.rewardPools[strategy];

        if (updatedPool.lastRewardTimestamp > pool.lastRewardTimestamp) {
            r.rewardPools[strategy] = pool;
        }
    }

    /* ========== ACL  ========== */

    /**
     * @notice Function which transfrFrom reward tokens from the sender and starts updates
     *         reward distribution.
     * TODO ACL
     * TODO Pausable
     */
    function notifyReward(
        address strategy,
        IERC20 rewardToken,
        uint256 rewardAmount,
        uint64 startTimestamp,
        uint64 distributionEnd
    ) external onlyNotStopped(strategy) nonReentrant {
        require(address(rewardToken) != address(0), ZeroAddress());
        require(startTimestamp >= block.timestamp, StartTimestampPassed());
        require(distributionEnd > startTimestamp, InvalidDistributionRange());

        updatePool(strategy);

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy];
        RewardPool storage pool = r.rewardPools[strategy];

        // TODO check if rewardInfo and pool is empty

        if (startTimestamp == 0) {
            startTimestamp = uint64(block.timestamp);
        }

        // tokens left from an earlier unfinished distribution
        uint256 leftover = _tokenReward(strategy);

        // override previous distribution
        rewardInfo.rewardToken = rewardToken;
        rewardInfo.distributionStart = startTimestamp;
        rewardInfo.distributionEnd = distributionEnd;

        // rate is rounded down (lose precision), so it should not exceed the available amount
        uint256 tokensPerSecond = (rewardAmount + leftover) / (distributionEnd - startTimestamp);
        require(tokensPerSecond <= 1e30, RateTooHigh());

        pool.tokensPerSecond = tokensPerSecond;
        pool.lastRewardTimestamp = startTimestamp;

        rewardToken.safeTransferFrom(msg.sender, address(this), rewardAmount + leftover);

        emit RewardNotify(
            strategy,
            address(rewardToken),
            rewardAmount,
            rewardAmount + leftover,
            startTimestamp,
            distributionEnd
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
        address strategy,
        address receiver
    ) external onlyStopped(strategy) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy];

        uint256 amount = _tokenReward(strategy);
        if(amount > 0) {
            rewardInfo.rewardToken.safeTransfer(receiver, amount);
            emit WithdrawRemaining(strategy, receiver, amount);
        }
    }

    // TODO ACL
    function stop(address strategy) external {
        updatePool(strategy);

        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy];

        uint64 stopped = uint64(block.timestamp);
        rewardInfo.stopped = stopped;
        emit Stop(strategy, msg.sender, stopped);
    }

    /* ========== VIEW ========== */

    /**
     * @notice View function to see unclaimed tokens
     * @param user Address of user.
     * @return pending reward for a given user.
     */
    function unclaimedTokens(address strategy, address user) external view returns (uint256) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        UserRewardInfo storage userInfo = r.userInfo[strategy][user];

        return  userInfo.tokensUnclaimed + _pendingTokens(strategy, user, _calculatePoolInfo(strategy));
    }

    /**
     * @notice View function to see balance of reward token.
     * TODO It should not work like this
     */
    function balance(address strategy) external view returns (uint256) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy];

        return rewardInfo.rewardToken.balanceOf(address(this));
    }

    function rewarderExist(address strategy) public view returns (bool) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy];

        if (address(rewardInfo.rewardToken) == address(0)) {
            return false;
        }
        return true;
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /**
     * @notice Returns current timestamp within token distribution or distribution end date
     */
    function _lastTimeRewardApplicable(address strategy) internal view returns (uint64) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        RewardInfo storage rewardInfo = r.rewardsInfo[strategy];

        if (rewardInfo.stopped > 0) {
            return rewardInfo.stopped;
        }

        return uint64(block.timestamp) > rewardInfo.distributionEnd
            ? rewardInfo.distributionEnd : uint64(block.timestamp);
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

    /**
     * @notice Helper function which calculates current pool info.
     * @dev Used for updating shares during pool update and for returning pendingTokens.
     */
    function _calculatePoolInfo(
        address strategy
    ) internal view returns (RewardPool memory pool) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vaultInfo = v.vaultInfo[strategy];

        RewarderStorage storage r = LibRewarder.diamondStorage();
        pool = r.rewardPools[strategy];

        // reward distribution didn't started yet
        if (pool.lastRewardTimestamp == 0) {
            return pool;
        }

        uint256 tokenReward = _tokenReward(strategy);
        if (tokenReward > 0) {
            if (vaultInfo.totalStakeLocked > 0) {
                // increase acctokenPerShare
                pool.accTokenPerShare +=
                    tokenReward * LibRewarder.REWARD_PRECISION
                    / vaultInfo.totalStakeLocked;
            }

            // update timestamp
            pool.lastRewardTimestamp = _lastTimeRewardApplicable(strategy);
        }
    }

    /**
     * @notice Internal function for pendingTokens.
     * @return pending reward for a given user.
     */
    function _pendingTokens(
        address strategy,
        address user,
        RewardPool memory pool
    ) internal view returns (uint256 pending) {
        RewarderStorage storage r = LibRewarder.diamondStorage();
        UserRewardInfo storage userInfo = r.userInfo[strategy][user];

        pending =
            userInfo.amount * pool.accTokenPerShare / LibRewarder.REWARD_PRECISION
            - userInfo.rewardPerTokenPaid;
    }
}
