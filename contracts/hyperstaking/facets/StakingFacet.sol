// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStaking} from "../interfaces/IStaking.sol";
import {ITier1Vault} from "../interfaces/ITier1Vault.sol";
import {ITier2Vault} from "../interfaces/ITier2Vault.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {HyperStakingStorage, LibHyperStaking, VaultInfo, VaultTier2} from "../libraries/LibHyperStaking.sol";

/**
 * @title StakingFacet
 * @notice Entry point for staking operations
 * Handles user deposits and withdrawals (tier1)
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract StakingFacet is IStaking, HyperStakingAcl, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using CurrencyHandler for Currency;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @notice Main Tier1 deposit function
    /// @inheritdoc IStaking
    function stakeDeposit(address strategy, uint256 stake, address to)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        VaultInfo storage vault = LibHyperStaking.diamondStorage().vaultInfo[strategy];
        require(vault.strategy != address(0), VaultDoesNotExist(strategy));

        vault.stakeCurrency.transferFrom(
            msg.sender,
            address(this),
            stake
        );
        ITier1Vault(address(this)).joinTier1(strategy, to, stake);

        emit StakeDeposit(msg.sender, to, strategy, stake, 1);
    }

    /// @notice Tier1 withdraw function
    /// @inheritdoc IStaking
    function stakeWithdraw(address strategy, uint256 stake, address to)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 withdrawAmount)
    {
        VaultInfo storage vault = LibHyperStaking.diamondStorage().vaultInfo[strategy];
        require(vault.strategy != address(0), VaultDoesNotExist(strategy));

        withdrawAmount = ITier1Vault(address(this)).leaveTier1(strategy, msg.sender, stake);

        vault.stakeCurrency.transfer(
            to,
            withdrawAmount
        );

        emit StakeWithdraw(msg.sender, to, strategy, stake, withdrawAmount);
    }

    /* ========== Tier 2  ========== */

    /// @notice Tier2 deposit function
    /// @inheritdoc IStaking
    function stakeDepositTier2(address strategy, uint256 stake, address to)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        require(vault.strategy != address(0), VaultDoesNotExist(strategy));

        VaultTier2 storage tier2 = v.vaultTier2Info[strategy];
        require(tier2.enabled, Tier2Disabled(strategy));

        vault.stakeCurrency.transferFrom(
            msg.sender,
            address(this),
            stake
        );
        ITier2Vault(address(this)).joinTier2(strategy, to, stake);

        emit StakeDeposit(msg.sender, to, strategy, stake, 2);
    }

    /* ========== ACL  ========== */

    /// @inheritdoc IStaking
    function pauseStaking() external onlyStakingManager whenNotPaused {
        _pause();
    }

    /// @inheritdoc IStaking
    function unpauseStaking() external onlyStakingManager whenPaused {
        _unpause();
    }
}
