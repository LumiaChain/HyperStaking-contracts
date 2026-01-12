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
import {LibHyperlaneReplayGuard} from "../../shared/libraries/LibHyperlaneReplayGuard.sol";

/**
 * @title DepositFacet
 * @notice Entry point for staking operations. Handles user deposits and withdrawals
 *
 * @dev This contract is a facet of Diamond Proxy
 */
contract DepositFacet is IDeposit, HyperStakingAcl, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using CurrencyHandler for Currency;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /* ========== Deposit ========== */

    /// @inheritdoc IDeposit
    function deposit(
        address strategy,
        address to,
        uint256 stake
    ) external payable nonReentrant whenNotPaused returns (uint256 requestId, uint256 allocation) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        _basicStakeChecks(vault, strategy, stake);

        v.stakeInfo[strategy].totalStake += stake;

        // quote the message fee for the cross-chain dispatch (to = dispatched user)
        uint256 dispatchFee = quoteDepositDispatch(strategy, to, stake);
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

        // bridge stake info to Lumia chain which mints coresponding rwa asset
        (requestId, allocation) = IAllocation(address(this)).joinSync(strategy, to, stake);

        emit Deposit(msg.sender, to, strategy, stake, requestId);
    }

    /// @inheritdoc IDeposit
    function requestDeposit(
        address strategy,
        address to,
        uint256 stake
    ) external payable nonReentrant whenNotPaused returns (uint256 requestId) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        _basicStakeChecks(vault, strategy, stake);

        v.stakeInfo[strategy].totalStake += stake;

        // true - bridge info to Lumia chain to mint coresponding rwa asset
        requestId = IAllocation(address(this)).joinAsync(strategy, to, stake);

        emit DepositRequest(msg.sender, to, strategy, stake, requestId);
    }

    /// @inheritdoc IDeposit
    function refundDeposit(
        address strategy,
        uint256 requestId,
        address to
    ) external nonReentrant whenNotPaused returns (uint256 stake) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        _basicChecks(vault, strategy);

        // get async request info from strategy
        (
            address user,
            bool isExit,
            ,
            ,
            ,
        ) = IStrategy(strategy).requestInfo(requestId);
        require(!isExit, BadRequestType());

        // strategy should validate requestId and return refunded stake amount
        stake = IAllocation(address(this)).refundJoinAsync(strategy, requestId, user, to);

        emit DepositRefund(msg.sender, to, strategy, stake, requestId);
    }

    /// @inheritdoc IDeposit
    function claimDeposit(
        address strategy,
        uint256 requestId
    ) external payable nonReentrant whenNotPaused returns (uint256 allocation) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        _basicChecks(vault, strategy);

        // get async request info from strategy
        (
            address user,
            bool isExit,
            uint256 stake,
            ,
            ,
            bool claimable
        ) = IStrategy(strategy).requestInfo(requestId);
        require(isExit, BadRequestType());
        require(claimable, RequestNotClaimable());

        // forward to allocation facet and execute the actual claim
        allocation = IAllocation(address(this)).claimJoinAsync(
            strategy,
            requestId,
            user,
            stake
        );

        uint256 dispatchFee = quoteDepositDispatch(strategy, user, stake);
        ILockbox(address(this)).collectDispatchFee{value: msg.value}(msg.sender, dispatchFee);

        emit Deposit(msg.sender, user, strategy, stake, requestId);
        return allocation;
    }

    /* ========== Withdraw ========== */

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

                emit FeeWithdrawClaimed(c.strategy, msg.sender, to, stake, exitAmount, id);
                continue;
            }

            // totalStake is not incremented by feeAmount
            v.stakeInfo[c.strategy].totalStake -= stake;
            v.stakeInfo[c.strategy].pendingExitStake -= stake;

            emit WithdrawClaimed(c.strategy, msg.sender, to, stake, exitAmount, id);
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

        v.pendingClaims[requestId] = Claim({
            strategy: strategy,
            unlockTime: readyAt,
            eligible: user,
            expectedAmount: stake,
            feeWithdraw: feeWithdraw
        });

        // data used for filtering
        v.groupedClaimIds[strategy][user].push(requestId);

        emit WithdrawQueued(strategy, user, readyAt, stake, feeWithdraw, requestId);
    }

    /// @inheritdoc IDeposit
    function refundWithdraw(
        uint256 requestId,
        address to
    ) external payable nonReentrant returns (uint256 allocationRefunded) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();

        require(to != address(0), ClaimToZeroAddress());

        Claim memory c = v.pendingClaims[requestId];

        uint256 stake = c.expectedAmount;

        require(c.strategy != address(0), ClaimNotFound(requestId));
        require(msg.sender == c.eligible, NotEligible(requestId, c.eligible, msg.sender));

        delete v.pendingClaims[requestId]; // remove realized claim

        uint256[] memory ids = new uint256[](1);
        ids[0] = requestId; // refund one

        // strategy refund exit, strategy should return allocation (shares) back to diamond
        allocationRefunded = IStrategy(c.strategy).refundExit(ids, address(this));

        // restore allocation back into totalAllocation
        // totalStake does not change here, because stake never left the strategy
        v.stakeInfo[c.strategy].totalAllocation += allocationRefunded;

        // exit was queued under either fee or user stake
        if (c.feeWithdraw) {
            v.stakeInfo[c.strategy].pendingExitFee -= stake;

            // Fee leave refunds stay local (no bridge), allocation is restored back to the diamond

            emit FeeLeaveRefunded(c.strategy, msg.sender, stake, allocationRefunded, requestId);
        } else {
            v.stakeInfo[c.strategy].pendingExitStake -= stake;

            // quote the message fee for the cross-chain dispatch (to = dispatched user)
            uint256 dispatchFee = quoteDepositDispatch(c.strategy, to, stake);
            ILockbox(address(this)).collectDispatchFee{value: msg.value}(msg.sender, dispatchFee);

            // bridge stake back to Lumia
            ILockbox(address(this)).bridgeStakeInfo(c.strategy, to, stake);

            emit WithdrawRefunded(c.strategy, msg.sender, to, stake, allocationRefunded, requestId);
        }
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
    function pendingClaims(
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
    function quoteDepositDispatch(
        address strategy,
        address user,
        uint256 stake
    ) public view returns (uint256) {
        StakeInfoData memory dispatchData = StakeInfoData({
            nonce: LibHyperlaneReplayGuard.previewNonce(),
            strategy: strategy,
            user: user,
            stake: stake
        });
        return IStakeInfoRoute(address(this)).quoteDispatchStakeInfo(dispatchData);
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice helper check function
    function _basicChecks(
        VaultInfo storage vault,
        address strategy
    ) internal view {
        require(vault.strategy != address(0), VaultDoesNotExist(strategy));
        require(vault.enabled, StrategyDisabled(strategy));
    }

    /// @notice helper check _basicChecks + stake
    function _basicStakeChecks(
        VaultInfo storage vault,
        address strategy,
        uint256 stake
    ) internal view {
        require(stake > 0, ZeroStake());
        _basicChecks(vault, strategy);
    }
}
