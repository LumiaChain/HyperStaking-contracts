// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IMasterChef} from "../interfaces/IMasterChef.sol";
import {ITokensRewarder} from "../interfaces/ITokensRewarder.sol";

import {LumiaDiamondAcl} from "../LumiaDiamondAcl.sol";

import {LibRewards, RewardsStorage} from "../libraries/LibRewards.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title MasterChefFacet
 * @notice Facet of a MasterChef contract that handles staking logic and tokens reward distribution
 */
contract MasterChefFacet is IMasterChef, LumiaDiamondAcl, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IMasterChef
    function stake(address token, uint256 amount) external nonReentrant {
        RewardsStorage storage r = LibRewards.diamondStorage();

        require(address(r.tokenRewarders[token]) != address(0), BadRewarder());
        require(amount > 0, ZeroStakeAmount());

        r.usersTokenStake[token][msg.sender] += amount;
        r.tokenTotalStake[token] += amount;

        r.tokenRewarders[token].updateActivePools(msg.sender);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, token, amount);
    }

    /// @inheritdoc IMasterChef
    function withdraw(address token, uint256 amount) external nonReentrant {
        RewardsStorage storage r = LibRewards.diamondStorage();

        require(amount > 0, ZeroWithdrawAmount());
        require(r.usersTokenStake[token][msg.sender] >= amount, ExceededWithdraw());

        r.usersTokenStake[token][msg.sender] -= amount;
        r.tokenTotalStake[token] -= amount;

        if (address(r.tokenRewarders[token]) != address(0)) {
            r.tokenRewarders[token].updateActivePools(msg.sender);
        }

        IERC20(token).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, token, amount);
    }

    /* ========== Rewards ========== */

    /// @inheritdoc IMasterChef
    function claim(address token, address user) external {
        LibRewards.diamondStorage().tokenRewarders[token].claimAll(user);
    }

    /// @inheritdoc IMasterChef
    function claimMultipleRewarders(address[] calldata rewarders, address user) external {
        for (uint256 i = 0; i < rewarders.length; i++){
            ITokensRewarder(rewarders[i]).claimAll(user);
        }
    }

    /* ========== ACL ========== */

    /// @inheritdoc IMasterChef
    function set(
        address token,
        ITokensRewarder rewarder
    ) external onlyLumiaRewardManager {
        require(token != address(0), ZeroTokenAddress());

        if(address(rewarder) != address(0)){
            // if rewarder was already set it should be finalized
            require(rewarder.finalizedAll(), ReplaceUnfinalizedRewarder());
        }

        RewardsStorage storage r = LibRewards.diamondStorage();
        ITokensRewarder currentRewarder = r.tokenRewarders[token];

        if(address(currentRewarder) != address(0)){
            // in case of incorrect rewarder contract use try/catch to still allow to set new rewarder
            try currentRewarder.finalizeAll() {} // solhint-disable-line no-empty-blocks
            catch {} // solhint-disable-line no-empty-blocks
        }

        r.tokenRewarders[token] = rewarder;

        emit Set(token, rewarder);
    }

    /**
     * @notice Updates the total stake limit for a given stake token
     * @dev If `limit` == 0 there is effectively no maximum stake limit
     */
    function setTokenStakeLimit(address stakeToken, uint256 limit) external onlyLumiaRewardManager {
        RewardsStorage storage r = LibRewards.diamondStorage();

        if (address(r.tokenRewarders[stakeToken]) == address(0)) {
            revert InvalidStakeToken(stakeToken);
        }

        // Update the stake limit
        r.tokenTotalStakeLimits[stakeToken] = limit;

        emit TokenStakeLimitSet(stakeToken, limit);
    }

    // ========= View ========= //

    /// @inheritdoc IMasterChef
    function rewardData(address token, uint256 distributionIdx, address user)
        external
        view
        returns (ITokensRewarder rewarder, IERC20 rewardToken, uint256 pendingReward)
    {
        RewardsStorage storage r = LibRewards.diamondStorage();

        rewarder = r.tokenRewarders[token];

        if (address(r.tokenRewarders[token]) != address(0)) {
            (rewardToken,) = rewarder.rewardInfo(distributionIdx);
            pendingReward = rewarder.pendingReward(distributionIdx ,user);
        }
    }

    /// @inheritdoc IMasterChef
    function getRewarder(address stakeToken) external view returns (ITokensRewarder) {
        RewardsStorage storage r = LibRewards.diamondStorage();
        return r.tokenRewarders[stakeToken];
    }

    /// @inheritdoc IMasterChef
    function getUserStake(address stakeToken, address user) external view returns (uint256) {
        RewardsStorage storage r = LibRewards.diamondStorage();
        return r.usersTokenStake[stakeToken][user];
    }

    /// @inheritdoc IMasterChef
    function getTotalStake(address stakeToken) external view returns (uint256) {
        RewardsStorage storage r = LibRewards.diamondStorage();
        return r.tokenTotalStake[stakeToken];
    }

    /// @inheritdoc IMasterChef
    function getTokenStakeLimit(address stakeToken) external view returns (uint256) {
        RewardsStorage storage r = LibRewards.diamondStorage();
        return r.tokenTotalStakeLimits[stakeToken];
    }
}
