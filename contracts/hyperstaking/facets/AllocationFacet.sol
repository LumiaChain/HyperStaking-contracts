// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IAllocation} from "../interfaces/IAllocation.sol";
import {IDeposit} from "../interfaces/IDeposit.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {ILockbox} from "../interfaces/ILockbox.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {
    LibHyperStaking, HyperStakingStorage, VaultInfo, StakeInfo
} from "../libraries/LibHyperStaking.sol";

/**
 * @title AllocationFacet
 * @notice Facet responsible for entering and exiting strategy positions
 *
 * @dev This contract is a facet of Diamond Proxy
 */
contract AllocationFacet is IAllocation, HyperStakingAcl, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using CurrencyHandler for Currency;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IAllocation
    function join(
        address strategy,
        address user,
        uint256 stake
    ) external payable diamondInternal {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        StakeInfo storage si = v.stakeInfo[strategy];

        // allocate stake amount in strategy
        // and receive allocation
        uint256 allocation;

        // Integrated strategy: all asset movements are handled internally by the IntegrationFacet
        if (IStrategy(strategy).isIntegratedStakeStrategy()) {
            // no-vaule and without increaseAllowance
            allocation = IStrategy(strategy).allocate(stake, user);
        } else {
            if (vault.stakeCurrency.isNativeCoin()) {
                allocation = IStrategy(strategy).allocate{value: stake}(stake, user);
            } else {
                vault.stakeCurrency.increaseAllowance(strategy, stake);
                allocation = IStrategy(strategy).allocate(stake, user);
            }
        }

        // save information
        si.totalAllocation += allocation;

        // bridge stakeInfo message to the Lumia diamond
        ILockbox(address(this)).bridgeStakeInfo(strategy, user, stake);

        emit Join(strategy, user, stake, allocation);
    }

    /// @inheritdoc IAllocation
    function leave(
        address strategy,
        address user,
        uint256 stake
    ) public diamondInternal nonReentrant returns (uint256 allocation) {
        return _leave(strategy, user, stake, false);
    }

    // ========= Vault Manager ========= //

    /// @inheritdoc IAllocation
    function report(address strategy)
        external
        onlyVaultManager
        nonReentrant
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        StakeInfo storage si = v.stakeInfo[strategy];
        _checkActiveStrategy(vault, strategy); // strategy validation

        address feeRecipient = vault.feeRecipient;
        require(feeRecipient != address(0), FeeRecipientUnset());

        uint256 revenue = checkRevenue(strategy);
        require(revenue > 0, InsufficientRevenue());

        uint256 feeAmount = vault.feeRate * revenue / LibHyperStaking.PERCENT_PRECISION;
        uint256 feeAllocation;

        if (feeAmount > 0) {
            feeAllocation = _leave(strategy, feeRecipient, feeAmount, true);
        }

        uint256 stakeAdded = revenue - feeAmount;

        // increase total stake value
        si.totalStake += stakeAdded;

        // bridge StakeReward message
        ILockbox(address(this)).bridgeStakeReward(strategy, stakeAdded);

        emit StakeCompounded(
            strategy,
            feeRecipient,
            vault.feeRate,
            feeAmount,
            feeAllocation,
            stakeAdded
        );
    }

    /// @inheritdoc IAllocation
    function setBridgeSafetyMargin(address strategy, uint256 newMargin) external onlyVaultManager {
        require(newMargin < LibHyperStaking.PERCENT_PRECISION, SafetyMarginTooHigh());
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        _checkActiveStrategy(vault, strategy); // validation

        uint256 oldMargin = vault.bridgeSafetyMargin;
        vault.bridgeSafetyMargin = newMargin;

        emit BridgeSafetyMarginUpdated(strategy, oldMargin, newMargin);
    }

    /// @inheritdoc IAllocation
    function setFeeRecipient(address strategy, address newRecipient) external onlyVaultManager {
        require(newRecipient != address(0), ZeroFeeRecipient());

        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        _checkActiveStrategy(vault, strategy); // strategy validation

        address oldRecipient = vault.feeRecipient;
        vault.feeRecipient = newRecipient;

        emit FeeRecipientUpdated(strategy, oldRecipient, newRecipient);
    }

    /// @inheritdoc IAllocation
    function setFeeRate(address strategy, uint256 newRate) external onlyVaultManager {
        require(newRate <= LibHyperStaking.MAX_FEE_RATE, FeeRateTooHigh());

        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        _checkActiveStrategy(vault, strategy); // strategy validation

        uint256 oldRate = vault.feeRate;
        vault.feeRate = newRate;

        emit FeeRateUpdated(strategy, oldRate, newRate);
    }

    // ========= View ========= //

    /// @inheritdoc IAllocation
    function stakeInfo(address strategy) external view returns (StakeInfo memory) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        return v.stakeInfo[strategy];
    }

    /// @inheritdoc IAllocation
    function checkRevenue(address strategy) public view returns (uint256) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();

        VaultInfo storage vault = v.vaultInfo[strategy];
        StakeInfo storage si = v.stakeInfo[strategy];

        // calculate total possible stake withdraw
        uint256 stake = IStrategy(strategy).previewExit(si.totalAllocation);

        // total stake that needs to be preserved for potential user bridge-outs
        uint256 bridgeCollateral = si.totalStake;

        // add safety margin to protect users from strategy asset volatility
        uint256 marginAmount = (
            bridgeCollateral * vault.bridgeSafetyMargin
        ) / LibHyperStaking.PERCENT_PRECISION;

        // check for negative revenue
        if (bridgeCollateral + marginAmount > stake) {
            return 0;
        }

        return stake - (bridgeCollateral + marginAmount);
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @dev leave actual implementation - without diamondInternal & nonReentrant
    function _leave(
        address strategy,
        address user,
        uint256 stake,
        bool feeWithdraw
    ) internal returns (uint256 allocation) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        StakeInfo storage si = v.stakeInfo[strategy];

        allocation = IStrategy(strategy).previewAllocation(stake);

        // save information
        si.totalAllocation -= allocation;


        // Integrated strategy does not require allowance
        if (!IStrategy(strategy).isIntegratedStakeStrategy()) {
            vault.revenueAsset.safeIncreaseAllowance(strategy, allocation);
        }
        // exit strategy with given allocation
        uint256 exitStake = IStrategy(strategy).exit(allocation, user);

        if (feeWithdraw) {
            IDeposit(address(this)).feeWithdraw(vault, user, exitStake);
        } else {
            IDeposit(address(this)).queueWithdraw(strategy, user, exitStake);
        }

        emit Leave(strategy, user, stake, exitStake, allocation);
    }

    /// @notice helper check function, strategy validation
    /// @dev unlike deposits, not enabled strategies are still available to the VaultManager operations
    function _checkActiveStrategy(
        VaultInfo storage vault,
        address strategy
    ) internal view {
        require(vault.strategy != address(0), StrategyDoesNotExist(strategy));
        require(!vault.direct, DirectStrategyNotAllowed(strategy));
    }
}
