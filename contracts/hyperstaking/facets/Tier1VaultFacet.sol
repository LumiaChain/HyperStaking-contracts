// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ITier1Vault} from "../interfaces/ITier1Vault.sol";
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
    LibStrategyVault, StrategyVaultStorage, UserVaultInfo, VaultInfo, VaultTier1
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
        uint256 amount
    ) external payable diamondInternal {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultTier1 storage tier1 = v.vaultTier1Info[strategy];

        StakingStorage storage s = LibStaking.diamondStorage();
        StakingPoolInfo storage pool = s.poolInfo[vault.poolId];

        {
            UserVaultInfo storage userVault = v.userInfo[strategy][user];
            UserPoolInfo storage userPool = s.userInfo[vault.poolId][user];

            userVault.allocationPoint = _calculateNewAllocPoint(
                userVault,
                strategy,
                amount
            );

            _lockUserStake(userPool, userVault, tier1, amount);
        }

        // allocate stake amount in strategy
        // and receive allocation
        uint256 allocation;
        if (pool.currency.isNativeCoin()) {
            allocation = IStrategy(strategy).allocate{value: amount}(amount, user);
        } else {
            pool.currency.approve(strategy, amount);
            allocation = IStrategy(strategy).allocate(amount, user);
        }

        // fetch allocation to this vault
        tier1.assetAllocation += allocation;
        vault.asset.safeTransferFrom(strategy, address(this), allocation);

        emit Tier1Join(vault.poolId, strategy, user, amount, allocation);
    }

    /// @inheritdoc ITier1Vault
    function leaveTier1(
        address strategy,
        address user,
        uint256 amount
    ) external diamondInternal returns (uint256 withdrawAmount) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultTier1 storage tier1 = v.vaultTier1Info[strategy];

        StakingStorage storage s = LibStaking.diamondStorage();

        uint256 revenueFeeAmount = _calcTier1RevenueFee(
            strategy,
            user,
            amount
        );

        uint256 allocation = _convertToTier1Allocation(tier1, amount);
        tier1.assetAllocation -= allocation;

        {
            UserVaultInfo storage userVault = v.userInfo[strategy][user];
            UserPoolInfo storage userPool = s.userInfo[vault.poolId][user];

            // withdraw does not change user allocation point
            _unlockUserStake(userPool, userVault, tier1, amount);
        }

        vault.asset.safeIncreaseAllowance(strategy, allocation);
        uint256 exitAmount = IStrategy(strategy).exit(allocation, user);

        withdrawAmount = exitAmount - revenueFeeAmount;

        emit Tier1Leave(vault.poolId, strategy, user, amount, allocation, revenueFeeAmount);
    }

    // ========= Managed ========= //

    /// @inheritdoc ITier1Vault
    function setRevenueFee(
        address strategy,
        uint256 revenueFee
    ) external onlyStrategyVaultManager nonReentrant {
        require(revenueFee <= 20e16, InvalidRevenueFeeValue()); // 20e16 == 20%

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
    function userContribution(address strategy, address user) public view returns (uint256) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();

        UserVaultInfo memory userVault = v.userInfo[strategy][user];
        VaultTier1 memory tier1 = v.vaultTier1Info[strategy];

        if (userVault.stakeLocked == 0) {
            return 0;
        }

        return userVault.stakeLocked * LibStaking.TOKEN_PRECISION_FACTOR / tier1.totalStakeLocked;
    }

    /// @inheritdoc ITier1Vault
    function userRevenue(address strategy, address user) public view returns (uint256 revenue) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();

        // current allocation price (stake to asset)
        uint8 assetDecimals = v.vaultInfo[strategy].asset.decimals();
        uint256 currentAllocationPrice = IStrategy(strategy).convertToAllocation(10**assetDecimals);

        UserVaultInfo storage userVault = v.userInfo[strategy][user];

        // allocation price hasn't increased, no revenue is generated
        if (currentAllocationPrice > userVault.allocationPoint) {
            return 0;
        }

        // calc the total amount to withdraw based on asset price and allocation point
        uint256 totalWithdraw =
            (userVault.allocationPoint * userVault.stakeLocked) / currentAllocationPrice;

        // difference between total withdrawable amount and locked stake
        revenue = totalWithdraw - userVault.stakeLocked;
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
     * @param amount The amount of stake to lock
     */
    function _lockUserStake(
        UserPoolInfo storage userPool,
        UserVaultInfo storage userVault,
        VaultTier1 storage tier1,
        uint256 amount
    ) internal {
        userPool.stakeLocked += amount;
        userVault.stakeLocked += amount;
        tier1.totalStakeLocked += amount;
    }

    /**
     * @notice Unlocks a specified stake amount for a user across pool, vault, and tier
     * @dev Decreases `stakeLocked` values in `userPool`, `userVault`, and `tier1`
     * @param userPool The user's pool info where locked stake is tracked
     * @param userVault The user's vault info where locked stake is tracked
     * @param tier1 The Tier 1 vault tracking total locked stake
     * @param amount The amount of stake to unlock
     */
    function _unlockUserStake(
        UserPoolInfo storage userPool,
        UserVaultInfo storage userVault,
        VaultTier1 storage tier1,
        uint256 amount
    ) internal {
        userPool.stakeLocked -= amount;
        userVault.stakeLocked -= amount;
        tier1.totalStakeLocked -= amount;
    }

    // ========= View ========= //

    /**
     * @notice Calculates the new allocation point
     * @dev This function calculates a potential new allocation point for the given user and amount
     * @param userVault The user's current vault information
     * @param strategy The strategy contract address, used for converting `amount` to an allocation
     * @param amount The new amount being hypothetically added to the user's locked stake
     * @return The calculated allocation point based on the weighted average
     */
    function _calculateNewAllocPoint(
        UserVaultInfo storage userVault,
        address strategy,
        uint256 amount
    ) internal view returns (uint256) {
        uint256 newAllocation = IStrategy(strategy).convertToAllocation(amount);

        // Weighted average calculation for the updated allocation point
        return (
            userVault.stakeLocked * userVault.allocationPoint
            + newAllocation * LibStaking.TOKEN_PRECISION_FACTOR
        ) / (userVault.stakeLocked + amount);
    }

    /**
     * @notice Converts stake amount to its Tier 1 allocation based on the total locked stake
     * @dev Calculates the allocation ratio of `amount` relative to `totalStakeLocked` and
     *      applies it to `assetAllocation`
     * @param tier1 The Tier 1 vault information, containing total locked stake and allocation
     * @param amount The amount to convert to Tier 1 allocation
     * @return The calculated Tier 1 allocation for the given amount
     */
    function _convertToTier1Allocation(
        VaultTier1 storage tier1,
        uint256 amount
    ) internal view returns (uint256) {
        // amout ratio of the total stake locked in vault
        uint256 amountRatio = amount * LibStaking.TOKEN_PRECISION_FACTOR / tier1.totalStakeLocked;
        return amountRatio * tier1.assetAllocation / LibStaking.TOKEN_PRECISION_FACTOR;
    }

    /**
     * @notice Calculates the revenue fee for a Tier 1 user based on their withdrawal amount
     * @dev Computes a proportional revenue fee amunt by adjusting the user's revenue according to
     *      the withdrawal amount and applying the strategy’s Tier 1 fee rate
     * @param strategy The strategy from which the user is exiting
     * @param user The address of the user
     * @param amount The amount the user wishes to withdraw
     * @return revenueFeeAmount The calculated revenue fee amount
     */
    function _calcTier1RevenueFee(
        address strategy,
        address user,
        uint256 amount
    ) internal view returns (uint256 revenueFeeAmount) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        UserVaultInfo storage userVault = v.userInfo[strategy][user];
        VaultTier1 storage tier1 = v.vaultTier1Info[strategy];

        uint256 withdrawRatio = amount * LibStaking.TOKEN_PRECISION_FACTOR / userVault.stakeLocked;
        uint256 revenue = userRevenue(strategy, user);
        uint256 revenuePart = revenue * withdrawRatio / LibStaking.TOKEN_PRECISION_FACTOR;
        revenueFeeAmount = revenuePart * tier1.revenueFee / LibStaking.TOKEN_PRECISION_FACTOR;
    }
}
