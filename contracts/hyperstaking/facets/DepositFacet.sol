// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IDeposit} from "../interfaces/IDeposit.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IStakeVault} from "../interfaces/IStakeVault.sol";
import {IStakeInfoRoute} from "../interfaces/IStakeInfoRoute.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {StakeInfoData} from "../libraries/HyperlaneMailboxMessages.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {
    HyperStakingStorage, LibHyperStaking, VaultInfo, StakeInfo, DirectStakeInfo
} from "../libraries/LibHyperStaking.sol";

/**
 * @title DepositFacet
 * @notice Entry point for staking operations. Handles user deposits and withdrawals
 *
 * @dev This contract is a facet of Diamond Proxy
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

    /* ========== Direct Staking ========== */

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

        _checkDeposit(vault, strategy, stake);

        v.directStakeInfo[strategy].totalStake += stake;

        vault.stakeCurrency.transferFrom(
            msg.sender,
            address(this),
            stake
        );

        StakeInfoData memory stakeData = StakeInfoData({
            strategy: strategy,
            sender: to,
            stakeAmount: stake,
            sharesAmount: 0
        });

        // quote bridge message fee
        uint256 fee = IStakeInfoRoute(address(this)).quoteDispatchStakeInfo(stakeData);

        // direct forwarding a StakeInfo message across chains
        IStakeInfoRoute(address(this)).stakeInfoDispatch{value: fee}(stakeData);

        emit StakeDeposit(msg.sender, to, strategy, stake, DepositType.Direct);
    }

    /// @notice Withdraw function (internal)
    /// @inheritdoc IDeposit
    function directStakeWithdraw(address strategy, uint256 stake, address to)
        external
        diamondInternal
        returns (uint256 withdrawAmount)
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        v.directStakeInfo[strategy].totalStake -= stake;

        vault.stakeCurrency.transfer(
            to,
            stake
        );

        withdrawAmount = stake;

        emit StakeWithdraw(address(this), to, strategy, stake, withdrawAmount, DepositType.Direct);
    }

    /* ========== Active Staking ========== */

    /// @notice Stake deposit function
    /// @inheritdoc IDeposit
    function stakeDeposit(address strategy, uint256 stake, address to)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        _checkDeposit(vault, strategy, stake);

        v.stakeInfo[strategy].totalStake += stake;

        vault.stakeCurrency.transferFrom(
            msg.sender,
            address(this),
            stake
        );

        // true - bridge info to Lumia chain to mint coresponding rwa asset
        IStakeVault(address(this)).join(strategy, to, stake);

        emit StakeDeposit(msg.sender, to, strategy, stake, DepositType.Active);
    }

    /// @notice Withdraw function (internal)
    /// @inheritdoc IDeposit
    function stakeWithdraw(address strategy, uint256 stake, address to)
        external
        diamondInternal
        returns (uint256 withdrawAmount)
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        StakeInfo storage stakeInfo = v.stakeInfo[strategy];

        // how many shares must be withdrawn from the vault to withdraw a given amount of stake
        uint256 allocation = IStrategy(strategy).previewAllocation(stake);

        // actual withdraw (ERC4626 withdraw)
        uint256 shares = stakeInfo.vaultToken.withdraw(allocation, to, address(this));
        withdrawAmount = IStrategy(strategy).previewExit(allocation);

        // save information
        stakeInfo.sharesRedeemed += shares; // TODO: remove?
        stakeInfo.stakeWithdrawn += withdrawAmount; // TODO: remove?

        stakeInfo.totalStake -= stake;

        emit StakeWithdraw(address(this), to, strategy, shares, withdrawAmount, DepositType.Active);
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

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice helper check function for deposits
    function _checkDeposit(
        VaultInfo storage vault,
        address strategy,
        uint256 stake
    ) internal view {
        require(stake > 0, ZeroStake());
        require(vault.strategy != address(0), VaultDoesNotExist(strategy));
        require(vault.enabled, StrategyDisabled(strategy));
    }
}
