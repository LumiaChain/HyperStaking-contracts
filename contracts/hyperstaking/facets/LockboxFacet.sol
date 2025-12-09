// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ILockbox} from "../interfaces/ILockbox.sol";
import {IAllocation} from "../interfaces/IAllocation.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {IStakeInfoRoute} from "../interfaces/IStakeInfoRoute.sol";
import {IStakeRewardRoute} from "../interfaces/IStakeRewardRoute.sol";

import {
    StakeInfoData, StakeRewardData, MessageType, HyperlaneMailboxMessages
} from "../libraries/HyperlaneMailboxMessages.sol";
import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../../external/hyperlane/libs/TypeCasts.sol";

import {NotAuthorized} from "../Errors.sol";

import {
    LibHyperStaking, LockboxData, FailedRedeem, FailedRedeemData, PendingMailbox, PendingLumiaFactory
} from "../libraries/LibHyperStaking.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title LockboxFacet
 * @notice A customized version of XERC20Lockbox and Factory for handling interchain communication
 *         via Hyperlane Mailbox. Handles incoming messages to initiate the redeem/unstaking process
 */
contract LockboxFacet is ILockbox, HyperStakingAcl {
    using HyperlaneMailboxMessages for bytes;
    using EnumerableSet for EnumerableSet.UintSet;

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    /// @notice Only accept messages from an Hyperlane Mailbox contract
    modifier onlyMailbox() {
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;
        require(
            msg.sender == address(box.mailbox),
            NotFromMailbox(msg.sender)
        );
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc ILockbox
    function bridgeStakeInfo(
        address strategy,
        address user,
        uint256 stake
    ) external payable diamondInternal {
        StakeInfoData memory data = StakeInfoData({
            strategy: strategy,
            sender: user,
            stake: stake
        });

        // quote message fee for forwarding a StakeInfo message across chains
        uint256 fee = IStakeInfoRoute(address(this)).quoteDispatchStakeInfo(data);

        // actual dispatch
        IStakeInfoRoute(address(this)).stakeInfoDispatch{value: fee}(data);
    }

    /// @inheritdoc ILockbox
    function bridgeStakeReward(
        address strategy,
        uint256 stakeAdded
    ) external payable diamondInternal {
        StakeRewardData memory data = StakeRewardData({
            strategy: strategy,
            stakeAdded: stakeAdded
        });

        // quote message fee for forwarding a StakeReward message across chains
        uint256 fee = IStakeRewardRoute(address(this)).quoteDispatchStakeReward(data);

        // actual dispatch
        IStakeRewardRoute(address(this)).stakeRewardDispatch{value: fee}(data);
    }

    /// @inheritdoc ILockbox
    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata data
    ) external payable onlyMailbox {
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;

        emit ReceivedMessage(origin, sender, msg.value, string(data));

        box.lastMessage.sender = TypeCasts.bytes32ToAddress(sender);
        box.lastMessage.data = data;

        require(
            box.lastMessage.sender == address(box.lumiaFactory),
            NotFromLumiaFactory(box.lastMessage.sender)
        );

        // parse message type (HyperlaneMailboxMessages)
        MessageType msgType = data.messageType();

        // route message
        if (msgType == MessageType.StakeRedeem) {
            _handleStakeRedeem(data);
            return;
        }

        revert UnsupportedMessage();
    }

    /* ========== Reexecute ========== */

    /// @inheritdoc ILockbox
    function reexecuteStakeRedeem(uint256 id) external {
        FailedRedeemData storage failedRedeems = LibHyperStaking.diamondStorage().failedRedeems;
        FailedRedeem memory fr = failedRedeems.failedRedeems[id];

        // both user or vault manager can reexecute
        require(
            hasRole(VAULT_MANAGER_ROLE(), msg.sender) ||
            msg.sender == fr.user,
            NotAuthorized(msg.sender)
        );

        delete failedRedeems.failedRedeems[id];
        failedRedeems.userToFailedIds[fr.user].remove(id);

        IAllocation(address(this)).leave(fr.strategy, fr.user, fr.amount);

        emit StakeRedeemReexecuted(fr.strategy, fr.user, fr.amount, id);
    }

    /* ========== ACL ========== */

    /// @inheritdoc ILockbox
    function setDestination(uint32 destination) external onlyVaultManager {
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;

        emit DestinationUpdated(box.destination, destination);
        box.destination = destination;
    }

    /// @inheritdoc ILockbox
    function proposeMailbox(address newMailbox) external onlyVaultManager {
        require(
            newMailbox != address(0) && newMailbox.code.length > 0,
            InvalidMailbox(newMailbox)
        );

        PendingMailbox memory pendingMailbox = PendingMailbox({
            newMailbox: newMailbox,
            applyAfter: block.timestamp + LibHyperStaking.PENDING_CHANGE_DELAY
        });

        LibHyperStaking.diamondStorage().pendingMailbox = pendingMailbox;

        emit MailboxChangeProposed(newMailbox, pendingMailbox.applyAfter);
    }

    /// @inheritdoc ILockbox
    function applyMailbox() external onlyVaultManager {
        PendingMailbox storage pendingMailbox = LibHyperStaking.diamondStorage().pendingMailbox;
        require(
            pendingMailbox.newMailbox != address(0) && block.timestamp >= pendingMailbox.applyAfter,
            PendingChangeFailed(pendingMailbox.newMailbox, pendingMailbox.applyAfter)
        );

        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;

        address oldMailbox = address(box.mailbox);
        box.mailbox = IMailbox(pendingMailbox.newMailbox);

        emit MailboxUpdated(oldMailbox, pendingMailbox.newMailbox);
        delete LibHyperStaking.diamondStorage().pendingMailbox;
    }

    /// @inheritdoc ILockbox
    function proposeLumiaFactory(address newFactory) external onlyVaultManager {
        require(newFactory != address(0), InvalidLumiaFactory(newFactory));

        PendingLumiaFactory memory pendingFactory = PendingLumiaFactory({
            newFactory: newFactory,
            applyAfter: block.timestamp + LibHyperStaking.PENDING_CHANGE_DELAY
        });

        LibHyperStaking.diamondStorage().pendingLumiaFactory = pendingFactory;

        emit LumiaFactoryChangeProposed(newFactory, pendingFactory.applyAfter);
    }

    /// @inheritdoc ILockbox
    function applyLumiaFactory() external onlyVaultManager {
        PendingLumiaFactory storage pendingFactory =
            LibHyperStaking.diamondStorage().pendingLumiaFactory;

        require(
            pendingFactory.newFactory != address(0) && block.timestamp >= pendingFactory.applyAfter,
            PendingChangeFailed(pendingFactory.newFactory, pendingFactory.applyAfter)
        );

        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;
        address oldFactory = box.lumiaFactory;
        box.lumiaFactory = pendingFactory.newFactory;

        emit LumiaFactoryUpdated(oldFactory, pendingFactory.newFactory);
        delete LibHyperStaking.diamondStorage().pendingLumiaFactory;
    }

    // ========= View ========= //

    /// @inheritdoc ILockbox
    function lockboxData() external view returns (LockboxData memory) {
        return LibHyperStaking.diamondStorage().lockboxData;
    }

    /// @inheritdoc ILockbox
    function getFailedRedeemCount() external view returns (uint256) {
        return LibHyperStaking.diamondStorage().failedRedeems.failedRedeemCount;
    }

    /// @inheritdoc ILockbox
    function getFailedRedeems(uint256[] calldata ids)
        external
        view
        returns (FailedRedeem[] memory)
    {
        FailedRedeemData storage s = LibHyperStaking.diamondStorage().failedRedeems;
        uint256 len = ids.length;

        FailedRedeem[] memory results = new FailedRedeem[](len);
        for (uint256 i = 0; i < len; ++i) {
            results[i] = s.failedRedeems[ids[i]];
        }

        return results;
    }

    /// @inheritdoc ILockbox
    function getUserFailedRedeemIds(address user) external view returns (uint256[] memory) {
        return LibHyperStaking.diamondStorage().failedRedeems.userToFailedIds[user].values();
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Handle specific StakeRedeem message
    /// @dev On failure, the action is stored for re-execution
    function _handleStakeRedeem(bytes calldata data) internal {
        address strategy = data.strategy();
        address user = data.sender(); // sender -> actual hyperstaking user
        uint256 stake = data.redeemAmount(); // amount -> amount of rwa asset / stake

        // solhint-disable-next-line no-empty-blocks
        try IAllocation(address(this)).leave(strategy, user, stake) {
            // success, nothing to do
        } catch {
            _storeFailedRedeem(strategy, user, stake);
        }
    }

    /// @notice Stores a failed redeem operation for later re-execution
    function _storeFailedRedeem(
        address strategy,
        address user,
        uint256 amount
    ) internal {
        FailedRedeemData storage failedRedeems = LibHyperStaking.diamondStorage().failedRedeems;

        uint256 id = failedRedeems.failedRedeemCount++;

        failedRedeems.failedRedeems[id] = FailedRedeem({
            strategy: strategy,
            user: user,
            amount: amount
        });

        failedRedeems.userToFailedIds[user].add(id);

        emit StakeRedeemFailed(strategy, user, amount, id);
    }
}
