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
    HyperStakingStorage, LibHyperStaking, VaultInfo, DirectStakeInfo, Claim
} from "../libraries/LibHyperStaking.sol";

/**
 * @title DepositFacet
 * @notice Entry point for staking operations. Handles user deposits and withdrawals
 *
 * @dev This contract is a facet of Diamond Proxy
 */
contract DepositFacet is IDeposit, HyperStakingAcl, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using CurrencyHandler for Currency;

    uint64 public constant MAX_WITHDRAW_DELAY = 30 days;

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

    /// @inheritdoc IDeposit
    function claimWithdraw(address strategy, address to) external {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        Claim storage claim = v.pendingClaims[msg.sender][strategy];

        // sender may withdraw only their own pending claim, but can forward it to any address (`to`)
        require(claim.amount > 0, ZeroClaim());
        require(
            block.timestamp >= claim.unlockTime,
            ClaimTooEarly(uint64(block.timestamp), claim.unlockTime)
        );

        VaultInfo storage vault = v.vaultInfo[strategy];
        uint256 stake = claim.amount;

        DepositType depositType;
        if (IStrategy(strategy).isDirectStakeStrategy()) {
            depositType = DepositType.Direct;
            v.directStakeInfo[strategy].totalStake -= stake;
        } else {
            depositType = DepositType.Active;
            v.stakeInfo[strategy].totalStake -= stake;
        }

        // reset claim
        claim.amount = 0;
        claim.unlockTime = 0;

        vault.stakeCurrency.transfer(
            to,
            stake
        );

        emit WithdrawClaimed(strategy, to, stake, depositType);
    }

    /// @notice Queues a stake withdrawal (internal)
    /// @inheritdoc IDeposit
    function queueWithdraw(
        address strategy,
        address to,
        uint256 stake
    ) external diamondInternal {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();

        uint64 unlockTime = uint64(block.timestamp) + v.withdrawDelay;
        v.pendingClaims[to][strategy] = Claim({
            amount: stake,
            unlockTime: unlockTime
        });

        emit WithdrawQueued(strategy, to, stake, unlockTime);
    }

    /// @notice Withdraw function for protocol fee (internal)
    /// @inheritdoc IDeposit
    function feeWithdraw(VaultInfo calldata vault, address feeRecipient, uint256 fee)
        external
        diamondInternal
    {
        vault.stakeCurrency.transfer(
            feeRecipient,
            fee
        );

        emit FeeWithdraw(feeRecipient, vault.strategy, fee);
    }

    /* ========== ACL ========== */

    /// @inheritdoc IDeposit
    function setWithdrawDelay(uint64 newDelay) external onlyStakingManager {
        require(newDelay < MAX_WITHDRAW_DELAY, WithdrawDelayTooHigh(newDelay));

        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        uint64 previousDelay = v.withdrawDelay;
        v.withdrawDelay = newDelay;

        emit WithdrawDelaySet(msg.sender, previousDelay, newDelay);
    }

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
    function withdrawDelay() external view returns (uint64) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        return v.withdrawDelay;
    }

    /// @inheritdoc IDeposit
    function pendingWithdraw(
        address user,
        address strategy
    ) external view returns (uint256 amount, uint256 unlockTime) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        Claim storage claim = v.pendingClaims[user][strategy];
        return (claim.amount, claim.unlockTime);
    }

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
