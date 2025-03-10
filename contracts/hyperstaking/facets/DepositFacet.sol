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
import {
    HyperStakingStorage, LibHyperStaking, VaultInfo, Tier2Info, DirectStakeInfo
} from "../libraries/LibHyperStaking.sol";

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

    /* ========== Direct Deposit ========== */

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

        v.directStakeInfo[strategy].totalStake += stake;

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

    /// @notice Tier2 withdraw function (internal)
    /// @inheritdoc IDeposit
    function directStakeWithdraw(address strategy, uint256 stake, address to)
        external
        whenNotPaused
        diamondInternal
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        v.directStakeInfo[strategy].totalStake -= stake;

        vault.stakeCurrency.transfer(
            to,
            stake
        );

        emit StakeWithdraw(address(this), to, strategy, stake, stake, DepositType.Direct);
    }

    /* ========== Tier 1  ========== */

    /// @notice Main Tier1 deposit function
    /// @inheritdoc IDeposit
    function stakeDepositTier1(address strategy, uint256 stake, address to)
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
    function stakeWithdrawTier1(address strategy, uint256 stake, address to)
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

        emit StakeWithdraw(msg.sender, to, strategy, stake, withdrawAmount, DepositType.Tier1);
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

    /// @notice Tier2 withdraw function (internal)
    /// @inheritdoc IDeposit
    function stakeWithdrawTier2(address strategy, uint256 stake, address to)
        external
        diamondInternal
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        Tier2Info storage tier2 = v.tier2Info[strategy];

        // how many shares must be withdrawn from the vault to withdraw a given amount of stake
        uint256 allocation = IStrategy(strategy).previewAllocation(stake);
        uint256 shares = tier2.vaultToken.previewWithdraw(allocation);

        // save information
        tier2.sharesRedeemed += shares;
        tier2.stakeWithdrawn += stake;

        // actual withdraw (ERC4626 withdraw)
        tier2.vaultToken.withdraw(allocation, to, address(this));

        emit StakeWithdraw(address(this), to, strategy, shares, stake, DepositType.Tier2);
    }

    /* ========== ACL ========== */

    /// @inheritdoc IDeposit
    function pauseDeposit() external onlyStakingManager whenNotPaused {
        _pause();
    }

    /// @inheritdoc IDeposit
    function unpauseDeposit() external onlyStakingManager whenPaused {
        _unpause();
    }

    // ========= View ========= //

    /// @inheritdoc IDeposit
    function directStakeInfo(address strategy) external view returns (DirectStakeInfo memory) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        return v.directStakeInfo[strategy];
    }
}
