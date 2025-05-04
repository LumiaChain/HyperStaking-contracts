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
        if (vault.stakeCurrency.isNativeCoin()) {
            allocation = IStrategy(strategy).allocate{value: stake}(stake, user);
        } else {
            vault.stakeCurrency.approve(strategy, stake);
            allocation = IStrategy(strategy).allocate(stake, user);
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
        uint256 allocation
    ) public diamondInternal nonReentrant returns (uint256 stake) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        StakeInfo storage si = v.stakeInfo[strategy];

        // save information
        si.totalAllocation += allocation;

        // exit strategy with given allocation
        vault.revenueAsset.safeIncreaseAllowance(strategy, allocation);
        stake = IStrategy(strategy).exit(allocation, user);

        IDeposit(address(this)).stakeWithdraw(strategy, user, stake);

        emit Leave(strategy, user, stake, allocation);
    }

    /// @inheritdoc IAllocation
    function collectRevenue(address strategy, address to, uint256 amount)
        external
        onlyVaultManager
    {
        uint256 revenue = checkRevenue(strategy);
        require(amount <= revenue, InsufficientRevenue());

        uint256 allocation = IStrategy(strategy).previewAllocation(amount);
        leave(strategy, to, allocation);

        emit RevenueCollected(strategy, to, amount);
    }

    /// @inheritdoc IAllocation
    function setBridgeSafetyMargin(address strategy, uint256 newMargin) external onlyVaultManager {
        require(newMargin >= LibHyperStaking.MIN_BRIDGE_SAFETY_MARGIN, SafetyMarginTooLow());

        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        StakeInfo storage si = v.stakeInfo[strategy];

        uint256 oldMargin = si.bridgeSafetyMargin;
        si.bridgeSafetyMargin = newMargin;

        emit BridgeSafetyMarginUpdated(oldMargin, newMargin);
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
        StakeInfo storage si = v.stakeInfo[strategy];

        // calculate total possible stake withdraw
        uint256 stake = IStrategy(strategy).previewExit(si.totalAllocation);

        // total stake that needs to be preserved for potential user bridge-outs
        uint256 bridgeCollateral = si.totalStake;

        // add safety margin to protect users from strategy asset volatility
        uint256 marginAmount = (
            bridgeCollateral * si.bridgeSafetyMargin
        ) / LibHyperStaking.PERCENT_PRECISION;

        // check for negative revenue
        if (bridgeCollateral + marginAmount > stake) {
            return 0;
        }

        return stake - (bridgeCollateral + marginAmount);
    }
}
