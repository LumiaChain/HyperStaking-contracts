// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IDeposit} from "../interfaces/IDeposit.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {ILockbox} from "../interfaces/ILockbox.sol";
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
 * @title DepositFacet
 * @notice Entry point for staking operations
 * Handles user deposits and withdrawals (tier1)
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract DepositFacet is IDeposit, HyperStakingAcl, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using CurrencyHandler for Currency;

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    modifier onlyDirect(address strategy) {
        require(IStrategy(strategy).isDirectStakeStrategy(), NotDirectDeposit(strategy));
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @notice Main Tier1 deposit function
    /// @inheritdoc IDeposit
    function stakeDeposit(address strategy, uint256 stake, address to)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        VaultInfo storage vault = LibHyperStaking.diamondStorage().vaultInfo[strategy];

        require(vault.strategy != address(0), VaultDoesNotExist(strategy));
        require(vault.enabled, StrategyDisabled(strategy));

        vault.stakeCurrency.transferFrom(
            msg.sender,
            address(this),
            stake
        );
        ITier1Vault(address(this)).joinTier1(strategy, to, stake);

        emit StakeDeposit(msg.sender, to, strategy, stake, DepositType.Tier1);
    }

    /// @notice Tier1 withdraw function
    /// @inheritdoc IDeposit
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
    /// @inheritdoc IDeposit
    function stakeDepositTier2(address strategy, uint256 stake, address to)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        require(vault.strategy != address(0), VaultDoesNotExist(strategy));
        require(vault.enabled, StrategyDisabled(strategy));

        vault.stakeCurrency.transferFrom(
            msg.sender,
            address(this),
            stake
        );
        ITier2Vault(address(this)).joinTier2(strategy, to, stake);

        emit StakeDeposit(msg.sender, to, strategy, stake, DepositType.Tier2);
    }

    /* ========== Simple Deposit ========== */

    /// @notice Direct stake deposit
    /// @inheritdoc IDeposit
    function directStakeDeposit(address strategy, uint256 stake, address to)
        external
        payable
        nonReentrant
        whenNotPaused
        onlyDirect(strategy)
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        require(vault.strategy != address(0), VaultDoesNotExist(strategy));
        require(vault.enabled, StrategyDisabled(strategy));

        vault.stakeCurrency.transferFrom(
            msg.sender,
            address(this),
            stake
        );

        // quote bridge message fee
        uint256 fee = ILockbox(address(this)).quoteDispatchStakeInfo(
            strategy,
            to,
            stake
        );

        // direct forwarding a StakeInfo message across chains
        ILockbox(address(this)).stakeInfoDispatch{value: fee}(
            strategy,
            to,
            stake
        );

        emit StakeDeposit(msg.sender, to, strategy, stake, DepositType.Direct);
    }

    /* ========== ACL  ========== */

    /// @inheritdoc IDeposit
    function pauseDeposit() external onlyStakingManager whenNotPaused {
        _pause();
    }

    /// @inheritdoc IDeposit
    function unpauseDeposit() external onlyStakingManager whenPaused {
        _unpause();
    }
}
