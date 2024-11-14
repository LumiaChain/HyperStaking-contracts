// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ITier1Vault} from "../interfaces/ITier1Vault.sol";
import {ITier2Vault} from "../interfaces/ITier2Vault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {
    LibStaking, StakingStorage, UserPoolInfo, StakingPoolInfo
} from "../libraries/LibStaking.sol";
import {
    LibStrategyVault, StrategyVaultStorage, UserTier1Info, VaultInfo, VaultTier1, VaultTier2
} from "../libraries/LibStrategyVault.sol";

/**
 * @title Tier1VaultFacet
 *
 * @dev This contract is a facet of Diamond Proxy
 */
contract Tier1VaultFacet is ITier1Vault, HyperStakingAcl, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using CurrencyHandler for Currency;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc ITier1Vault
    function joinTier1(
        address strategy,
        address user,
        uint256 stake
    ) external payable diamondInternal {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultTier1 storage tier1 = v.vaultTier1Info[strategy];

        StakingStorage storage s = LibStaking.diamondStorage();
        StakingPoolInfo storage pool = s.poolInfo[vault.poolId];

        { // lock stake
            UserTier1Info storage userVault = v.userInfo[strategy][user];
            UserPoolInfo storage userPool = s.userInfo[vault.poolId][user];

            userVault.allocationPoint = _calculateNewAllocPoint(
                userVault,
                strategy,
                stake
            );

            _lockUserStake(userPool, userVault, tier1, stake);
        }

        // allocate stake amount in strategy
        // and receive allocation
        uint256 allocation;
        if (pool.currency.isNativeCoin()) {
            allocation = IStrategy(strategy).allocate{value: stake}(stake, user);
        } else {
            pool.currency.approve(strategy, stake);
            allocation = IStrategy(strategy).allocate(stake, user);
        }

        // fetch allocation to this vault
        tier1.assetAllocation += allocation;
        vault.asset.safeTransferFrom(strategy, address(this), allocation);

        emit Tier1Join(strategy, user, stake, allocation);
    }

    /// @inheritdoc ITier1Vault
    function leaveTier1(
        address strategy,
        address user,
        uint256 stake
    ) external diamondInternal returns (uint256 withdrawAmount) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        uint256 exitAllocation = _leaveTier1(strategy, user, stake);

        vault.asset.safeIncreaseAllowance(strategy, exitAllocation);
        withdrawAmount = IStrategy(strategy).exit(exitAllocation, user);
    }

    /// @inheritdoc ITier1Vault
    function migrateToTier2(address strategy, uint256 stake) external {
        // use msg.sender to leave tier1 and join tier2
        uint256 exitAllocation = _leaveTier1(strategy, msg.sender, stake);

        { // decrease user and pool stake
            StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
            VaultInfo storage vault = v.vaultInfo[strategy];

            StakingStorage storage s = LibStaking.diamondStorage();
            StakingPoolInfo storage pool = s.poolInfo[vault.poolId];
            UserPoolInfo storage userPool = s.userInfo[vault.poolId][msg.sender];

            pool.totalStake -= stake;
            userPool.staked -= stake;
        }

        ITier2Vault(address(this)).joinTier2WithAllocation(strategy, msg.sender, exitAllocation);
    }

    // ========= Managed ========= //

    /// @inheritdoc ITier1Vault
    function setRevenueFee(
        address strategy,
        uint256 revenueFee
    ) external onlyStrategyVaultManager nonReentrant {
        uint256 onePercent = LibStrategyVault.PERCENT_PRECISION / 100;
        require(revenueFee <= 30 * onePercent, InvalidRevenueFeeValue());

        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        v.vaultTier1Info[strategy].revenueFee = revenueFee;
    }

    // ========= View ========= //

    /// @inheritdoc ITier1Vault
    function vaultTier1Info(address strategy) external view returns (VaultTier1 memory) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        return v.vaultTier1Info[strategy];
    }

    /// @inheritdoc ITier1Vault
    function userTier1Info(
        address strategy,
        address user
    ) external view returns (UserTier1Info  memory) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        return v.userInfo[strategy][user];
    }

    /// @inheritdoc ITier1Vault
    function userContribution(address strategy, address user) public view returns (uint256) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();

        UserTier1Info memory userVault = v.userInfo[strategy][user];
        VaultTier1 memory tier1 = v.vaultTier1Info[strategy];

        if (userVault.stakeLocked == 0) {
            return 0;
        }

        return userVault.stakeLocked * LibStrategyVault.PERCENT_PRECISION / tier1.totalStakeLocked;
    }

    /// @inheritdoc ITier1Vault
    function allocationGain(
        address strategy,
        address user,
        uint256 stake
    ) public view returns (uint256) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        UserTier1Info storage userVault = v.userInfo[strategy][user];

        uint256 currentAllocationPrice = _currentAllocationPrice(strategy);

        // allocation price hasn't increased, no fee is generated
        if (currentAllocationPrice > userVault.allocationPoint) {
            return 0;
        }

        // s * all_point = all
        // s * all_current = all + gain
        //
        // gain = s (all_point - all_current)
        return
            stake * (userVault.allocationPoint - currentAllocationPrice)
            / LibStrategyVault.ALLOCATION_POINT_PRECISION;
    }

    /// @inheritdoc ITier1Vault
    function allocationFee(
        address strategy,
        uint256 allocation
    ) public view returns (uint256 feeAmount) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultTier1 storage tier1 = v.vaultTier1Info[strategy];
        return allocation * tier1.revenueFee / LibStrategyVault.PERCENT_PRECISION;
    }

    /// @inheritdoc ITier1Vault
    function userRevenue(address strategy, address user) public view returns (uint256 revenue) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        UserTier1Info storage userVault = v.userInfo[strategy][user];

        // use the whole user locked stake
        uint256 gain = allocationGain(strategy, user, userVault.stakeLocked);

        // no revenue is generated
        if (gain == 0) {
            return 0;
        }

        uint256 fee = allocationFee(strategy, gain);

        return IStrategy(strategy).convertToStake(gain - fee);
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /**
     * @notice Locks a specified stake amount for a user across pool, vault, and tier
     * @dev Increases `stakeLocked` values in `userPool`, `userVault`, and `tier1`
     * @param userPool The user's pool info where locked stake is tracked
     * @param userVault The user's vault info where locked stake is tracked
     * @param tier1 The Tier 1 vault tracking total locked stake
     * @param stake The amount of stake to lock
     */
    function _lockUserStake(
        UserPoolInfo storage userPool,
        UserTier1Info storage userVault,
        VaultTier1 storage tier1,
        uint256 stake
    ) internal {
        userPool.stakeLocked += stake;
        userVault.stakeLocked += stake;
        tier1.totalStakeLocked += stake;
    }

    /**
     * @notice Unlocks a specified stake amount for a user across pool, vault, and tier
     * @dev Decreases `stakeLocked` values in `userPool`, `userVault`, and `tier1`
     * @param userPool The user's pool info where locked stake is tracked
     * @param userVault The user's vault info where locked stake is tracked
     * @param tier1 The Tier 1 vault tracking total locked stake
     * @param stake The amount of stake to unlock
     */
    function _unlockUserStake(
        UserPoolInfo storage userPool,
        UserTier1Info storage userVault,
        VaultTier1 storage tier1,
        uint256 stake
    ) internal {
        userPool.stakeLocked -= stake;
        userVault.stakeLocked -= stake;
        tier1.totalStakeLocked -= stake;
    }

    /**
     * @notice Implementation of leaveTier1
     * @dev Without exiting strategy,
     *      shared code used in stake withdrawal, but also during migration
     * @return exitAllocation allocation which could be exited from strategy
     */
    function _leaveTier1(
        address strategy,
        address user,
        uint256 stake
    ) internal returns (uint256 exitAllocation) {

        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultTier1 storage tier1 = v.vaultTier1Info[strategy];
        VaultTier2 storage tier2 = v.vaultTier2Info[strategy];

        StakingStorage storage s = LibStaking.diamondStorage();
        UserPoolInfo storage userPool = s.userInfo[vault.poolId][user];

        require(userPool.stakeLocked >= stake, InsufficientStakeLocked());

        uint256 allocation = _convertToAllocation(tier1, stake);
        tier1.assetAllocation -= allocation;

        { // unlock stake
            UserTier1Info storage userVault = v.userInfo[strategy][user];

            // withdraw does not change user allocation point
            _unlockUserStake(userPool, userVault, tier1, stake);
        }

        // allocation fee on gain
        uint256 fee = allocationFee(
            strategy,
            allocationGain(strategy, user, stake)
        );

        if (fee > 0) {
            vault.asset.safeTransfer(address(tier2.vaultToken), fee);
        }

        emit Tier1Leave(strategy, user, stake, allocation, fee);

        exitAllocation = allocation - fee;
    }

    // ========= View ========= //

    /**
     * @notice Calculates the new allocation point
     * @dev This function calculates a potential new allocation point for the given user and amount
     * @param userVault The user's current vault information
     * @param strategy The strategy contract address, used for converting `stake` to an allocation
     * @param stake The new amount being hypothetically added to the user's locked stake
     * @return The calculated allocation point based on the weighted average
     */
    function _calculateNewAllocPoint(
        UserTier1Info storage userVault,
        address strategy,
        uint256 stake
    ) internal view returns (uint256) {
        uint256 newAllocation = IStrategy(strategy).convertToAllocation(stake);

        // Weighted average calculation for the updated allocation point
        return (
            userVault.stakeLocked * userVault.allocationPoint
            + newAllocation * LibStrategyVault.PERCENT_PRECISION
        ) / (userVault.stakeLocked + stake);
    }

    /**
     * @notice Converts stake amount to its Tier 1 allocation based on the total locked stake
     * @dev Calculates the allocation ratio of `stake` relative to `totalStakeLocked` and
     *      applies it to `assetAllocation`
     * @param tier1 The Tier 1 vault information, containing total locked stake and allocation
     * @param stake The stake amount to convert to Tier 1 allocation
     * @return The calculated Tier 1 allocation for the given stake amount
     */
    function _convertToAllocation(
        VaultTier1 storage tier1,
        uint256 stake
    ) internal view returns (uint256) {
        // amout ratio of the total stake locked in vault
        uint256 amountRatio = stake * LibStrategyVault.PERCENT_PRECISION / tier1.totalStakeLocked;
        return amountRatio * tier1.assetAllocation / LibStrategyVault.PERCENT_PRECISION;
    }

    /**
     * @dev Helper
     * @dev Price uses asset precision (decimals)
     * @param strategy The strategy contract address, used for converting `stake` to an allocation
     * @return Current allocation price (expresed in base stake unit -> to asset)
     */
    function _currentAllocationPrice(address strategy) internal view returns (uint256) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        StakingStorage storage s = LibStaking.diamondStorage();
        StakingPoolInfo storage pool = s.poolInfo[vault.poolId];

        // current allocation price (stake to asset)
        uint8 stakeDecimals = pool.currency.decimals();
        return IStrategy(strategy).convertToAllocation(10 ** stakeDecimals);
    }
}
