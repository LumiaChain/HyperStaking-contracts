// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IDeposit} from "../interfaces/IDeposit.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IAllocation} from "../interfaces/IAllocation.sol";
import {ILockbox} from "../interfaces/ILockbox.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {
    HyperStakingStorage, LibHyperStaking, VaultInfo, DirectStakeInfo
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
    function directStakeDeposit(address strategy, address to, uint256 stake)
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

        // direct forwarding a StakeInfo message across chains
        ILockbox(address(this)).bridgeStakeInfo(strategy, to, stake);

        emit StakeDeposit(msg.sender, to, strategy, stake, DepositType.Direct);
    }

    /* ========== Active Staking ========== */

    /// @notice Stake deposit function
    /// @inheritdoc IDeposit
    function stakeDeposit(address strategy, address to, uint256 stake)
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
        IAllocation(address(this)).join(strategy, to, stake);

        emit StakeDeposit(msg.sender, to, strategy, stake, DepositType.Active);
    }

    /* ========== Stake Withdraw ========== */

    /// @notice Withdraw function (internal)
    /// @inheritdoc IDeposit
    function stakeWithdraw(address strategy, address to, uint256 stake)
        external
        diamondInternal
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        v.directStakeInfo[strategy].totalStake -= stake;

        vault.stakeCurrency.transfer(
            to,
            stake
        );

        DepositType depositType;
        if (IStrategy(strategy).isDirectStakeStrategy()) {
            depositType = DepositType.Direct;
        } else {
            depositType = DepositType.Active;
        }

        emit StakeWithdraw(address(this), to, strategy, stake, depositType);
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
