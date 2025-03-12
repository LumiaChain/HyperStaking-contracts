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
    LibHyperStaking, HyperStakingStorage, UserTier1Info, VaultInfo, Tier1Info, Tier2Info
} from "../libraries/LibHyperStaking.sol";

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
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        Tier1Info storage tier1 = v.tier1Info[strategy];

        { // alloc point, lock
            UserTier1Info storage userVault = v.userInfo[strategy][user];

            userVault.allocationPoint = _calculateNewAllocPoint(
                userVault,
                strategy,
                stake
            );

            _lockUserStake(userVault, tier1, stake);
        }

        // stake into strategy and receive allocation amount
        uint256 allocation;
        if (vault.stakeCurrency.isNativeCoin()) {
            allocation = IStrategy(strategy).allocate{value: stake}(stake, user);
        } else {
            vault.stakeCurrency.approve(strategy, stake);
            allocation = IStrategy(strategy).allocate(stake, user);
        }

        // fetch allocation
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
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        uint256 exitAllocation = _leaveTier1(strategy, user, stake);

        vault.asset.safeIncreaseAllowance(strategy, exitAllocation);
        withdrawAmount = IStrategy(strategy).exit(exitAllocation, user);
    }

    // ========= Managed ========= //

    /// @inheritdoc ITier1Vault
    function setRevenueFee(
        address strategy,
        uint256 revenueFee
    ) external onlyVaultManager nonReentrant {
        uint256 onePercent = LibHyperStaking.PERCENT_PRECISION / 100;
        require(revenueFee <= 30 * onePercent, InvalidRevenueFeeValue());

        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        v.tier1Info[strategy].revenueFee = revenueFee;

        emit RevenueFeeSet(strategy, revenueFee);
    }

    // ========= View ========= //

    /// @inheritdoc ITier1Vault
    function tier1Info(address strategy) external view returns (Tier1Info memory) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        return v.tier1Info[strategy];
    }

    /// @inheritdoc ITier1Vault
    function userTier1Info(
        address strategy,
        address user
    ) external view returns (UserTier1Info  memory) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        return v.userInfo[strategy][user];
    }

    /// @inheritdoc ITier1Vault
    function userContribution(address strategy, address user) public view returns (uint256) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();

        UserTier1Info memory userVault = v.userInfo[strategy][user];
        Tier1Info memory tier1 = v.tier1Info[strategy];

        if (userVault.stake== 0) {
            return 0;
        }

        return userVault.stake * LibHyperStaking.PERCENT_PRECISION / tier1.totalStake;
    }

    /// @inheritdoc ITier1Vault
    function allocationGain(
        address strategy,
        address user,
        uint256 stake
    ) public view returns (uint256) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
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
            / LibHyperStaking.ALLOCATION_POINT_PRECISION;
    }

    /// @inheritdoc ITier1Vault
    function allocationFee(
        address strategy,
        uint256 allocation
    ) public view returns (uint256 feeAmount) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        Tier1Info storage tier1 = v.tier1Info[strategy];
        return allocation * tier1.revenueFee / LibHyperStaking.PERCENT_PRECISION;
    }

    /// @inheritdoc ITier1Vault
    function userRevenue(address strategy, address user) public view returns (uint256 revenue) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        UserTier1Info storage userVault = v.userInfo[strategy][user];

        // use the whole user locked stake
        uint256 gain = allocationGain(strategy, user, userVault.stake);

        // no revenue is generated
        if (gain == 0) {
            return 0;
        }

        uint256 fee = allocationFee(strategy, gain);

        return IStrategy(strategy).previewExit(gain - fee);
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /**
     * @notice Locks a specified stake amount for a user across vault, and tier
     * @dev Increases `stake` values in `userVault`, and `tier1`
     * @param userVault The user's vault info where locked stake is tracked
     * @param tier1 The Tier 1 vault tracking total locked stake
     * @param stake The amount of stake to lock
     */
    function _lockUserStake(
        UserTier1Info storage userVault,
        Tier1Info storage tier1,
        uint256 stake
    ) internal {
        userVault.stake += stake;
        tier1.totalStake += stake;
    }

    /**
     * @notice Unlocks a specified stake amount for a user across vault, and tier
     * @dev Decreases `stake` values in `userVault`, and `tier1`
     * @param userVault The user's vault info where locked stake is tracked
     * @param tier1 The Tier 1 vault tracking total locked stake
     * @param stake The amount of stake to unlock
     */
    function _unlockUserStake(
        UserTier1Info storage userVault,
        Tier1Info storage tier1,
        uint256 stake
    ) internal {
        userVault.stake -= stake;
        tier1.totalStake -= stake;
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
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        Tier1Info storage tier1 = v.tier1Info[strategy];
        Tier2Info storage tier2 = v.tier2Info[strategy];

        uint256 allocation = _convertToAllocation(tier1, stake);
        tier1.assetAllocation -= allocation;

        { // unlock
            UserTier1Info storage userVault = v.userInfo[strategy][user];

            // reverts error if unlock amount exceeds available stake
            require(userVault.stake >= stake, InsufficientStake());

            // withdraw does not change user allocation point
            _unlockUserStake(userVault, tier1, stake);
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
        uint256 newAllocation = IStrategy(strategy).previewAllocation(stake);

        // Weighted average calculation for the updated allocation point
        return (
            userVault.stake * userVault.allocationPoint
            + newAllocation * LibHyperStaking.PERCENT_PRECISION
        ) / (userVault.stake + stake);
    }

    /**
     * @notice Converts stake amount to its Tier 1 allocation based on the total locked stake
     * @dev Calculates the allocation ratio of `stake` relative to `totalStake` and
     *      applies it to `assetAllocation`
     * @param tier1 The Tier 1 vault information, containing total locked stake and allocation
     * @param stake The stake amount to convert to Tier 1 allocation
     * @return The calculated Tier 1 allocation for the given stake amount
     */
    function _convertToAllocation(
        Tier1Info storage tier1,
        uint256 stake
    ) internal view returns (uint256) {
        // amout ratio of the total stake locked in vault
        uint256 amountRatio = stake * LibHyperStaking.PERCENT_PRECISION / tier1.totalStake;
        return amountRatio * tier1.assetAllocation / LibHyperStaking.PERCENT_PRECISION;
    }

    /**
     * @dev Helper
     * @dev Price uses asset precision (decimals)
     * @param strategy The strategy contract address, used for converting `stake` to an allocation
     * @return Current allocation price (expresed in base stake unit -> to asset)
     */
    function _currentAllocationPrice(address strategy) internal view returns (uint256) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        // current allocation price (stake to asset)
        uint8 stakeDecimals = vault.stakeCurrency.decimals();
        return IStrategy(strategy).previewAllocation(10 ** stakeDecimals);
    }
}
