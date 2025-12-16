// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IDeposit} from "../interfaces/IDeposit.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IAllocation} from "../interfaces/IAllocation.sol";
import {IStakeInfoRoute} from "../interfaces/IStakeInfoRoute.sol";
import {ILockbox} from "../interfaces/ILockbox.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {StakeInfoData} from "../../shared/libraries/HyperlaneMailboxMessages.sol";
import {
    HyperStakingStorage, LibHyperStaking, VaultInfo, Claim
} from "../libraries/LibHyperStaking.sol";

import {Currency, CurrencyHandler} from "../../shared/libraries/CurrencyHandler.sol";

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
    //                                      Public Functions                                      //
    //============================================================================================//

    /* ========== Deposit ========== */

    /// @notice Stake deposit function
    /// @inheritdoc IDeposit
    function stakeDeposit(
        address strategy,
        address to,
        uint256 stake
    ) external payable nonReentrant whenNotPaused {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        _checkDeposit(vault, strategy, stake);

        v.stakeInfo[strategy].totalStake += stake;

        // quote message fee for forwarding message across chains
        uint256 dispatchFee = quoteStakeDeposit(strategy, to, stake);
        if (vault.stakeCurrency.isNativeCoin()) {
            vault.stakeCurrency.transferFrom(
                msg.sender,
                address(this),
                stake + dispatchFee // include fee to stake amount
            );
        } else { // fetch native and tokens separately
            ILockbox(address(this)).collectDispatchFee{value: msg.value}(msg.sender, dispatchFee);

            // stake
            vault.stakeCurrency.transferFrom(
                msg.sender,
                address(this),
                stake
            );
        }

        // true - bridge info to Lumia chain to mint coresponding rwa asset
        IAllocation(address(this)).join(strategy, to, stake);

        emit StakeDeposit(msg.sender, to, strategy, stake);
    }

    /* ========== Stake Withdraw ========== */

    /// @inheritdoc IDeposit
    function claimWithdraws(uint256[] calldata requestIds, address to) external {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        uint256 n = requestIds.length;

        require(n > 0, EmptyClaim());
        require(to != address(0), ClaimToZeroAddress());

        for (uint256 i = 0; i < n; ++i) {
            uint256 id = requestIds[i];
            Claim memory c = v.pendingClaims[id];

            uint256 stake = c.expectedAmount;

            require(c.strategy != address(0), ClaimNotFound(id));
            require(msg.sender == c.eligible, NotEligible(id, c.eligible, msg.sender));
            require(
                block.timestamp >= c.unlockTime,
                ClaimTooEarly(uint64(block.timestamp), c.unlockTime)
            );

            delete v.pendingClaims[id]; // remove realized claim

            // claim one by one, as strategy may not support array claims
            uint256[] memory ids = new uint256[](1);
            ids[0] = id;

            // The final exitAmount may differ from the expected stake
            // because of possible price changes between request and claim,
            uint256 exitAmount = IStrategy(c.strategy).claimExit(ids, to);

            if (c.feeWithdraw) {
                v.stakeInfo[c.strategy].pendingExitFee -= stake;

                emit FeeWithdrawClaimed(c.strategy, msg.sender, to, stake, exitAmount);
                continue;
            }

            // totalStake is not incremented by feeAmount
            v.stakeInfo[c.strategy].totalStake -= stake;
            v.stakeInfo[c.strategy].pendingExitStake -= stake;

            emit WithdrawClaimed(c.strategy, msg.sender, to, stake, exitAmount);
        }
    }

    /// @notice Queues a withdrawal (internal)
    /// @inheritdoc IDeposit
    function queueWithdraw(
        address strategy,
        address user,
        uint256 stake,
        uint256 allocation,
        bool feeWithdraw
    ) external diamondInternal {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();

        // request exit from the strategy with given allocation
        uint256 requestId = LibHyperStaking.newRequestId();
        uint64 readyAt = IStrategy(strategy).requestExit(requestId, allocation, user);

        if (readyAt == 0 && !feeWithdraw) {
            readyAt = uint64(block.timestamp) + v.defaultWithdrawDelay;
        }

        v.pendingClaims[requestId] = Claim({
            strategy: strategy,
            unlockTime: readyAt,
            eligible: user,
            expectedAmount: stake,
            feeWithdraw: feeWithdraw
        });

        // data used for filtering
        v.groupedClaimIds[strategy][user].push(requestId);

        emit WithdrawQueued(strategy, user, requestId, readyAt, stake, feeWithdraw);
    }

    /* ========== ACL ========== */

    /// @inheritdoc IDeposit
    function setWithdrawDelay(uint64 newDelay) external onlyStakingManager {
        require(newDelay < MAX_WITHDRAW_DELAY, WithdrawDelayTooHigh(newDelay));

        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        uint64 previousDelay = v.defaultWithdrawDelay;
        v.defaultWithdrawDelay = newDelay;

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
        return v.defaultWithdrawDelay;
    }

    /// @inheritdoc IDeposit
    function pendingWithdraws(
        uint256[] calldata requestIds
    ) external view returns (Claim[] memory claims) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();

        uint256 n = requestIds.length;
        claims = new Claim[](n);

        for (uint256 i = 0; i < n; ++i) {
            uint256 requestId = requestIds[i];
            claims[i] = v.pendingClaims[requestId];
        }
    }

    /// @inheritdoc IDeposit
    function lastClaims(
        address strategy,
        address user,
        uint256 limit
    ) external view returns (uint256[] memory ids) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        uint256[] storage arr = v.groupedClaimIds[strategy][user];

        uint256 len = arr.length;
        if (limit > len) {
            limit = len;
        }

        ids = new uint256[](limit);
        for (uint256 i; i < limit; ++i) {
            ids[i] = arr[len - 1 - i];
        }
    }

    /// @inheritdoc IDeposit
    function quoteStakeDeposit(
        address strategy,
        address to,
        uint256 stake
    ) public view returns (uint256) {
        StakeInfoData memory dispatchData = StakeInfoData({
            strategy: strategy,
            sender: to, // actually to is used as the dispatch sender in lockbox
            stake: stake
        });
        return IStakeInfoRoute(address(this)).quoteDispatchStakeInfo(dispatchData);
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
