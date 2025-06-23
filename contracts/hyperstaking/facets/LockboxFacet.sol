// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ILockbox} from "../interfaces/ILockbox.sol";
import {IDeposit} from "../interfaces/IDeposit.sol";
import {IAllocation} from "../interfaces/IAllocation.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
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
    LibHyperStaking, LockboxData, FailedRedeem, FailedRedeemData
} from "../libraries/LibHyperStaking.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title LockboxFacet
 * @notice A customized version of XERC20Lockbox and Factory for handling interchain communication
 *         via Hyperlane Mailbox. Locks DirectStake assets or VaultTokens shares
 *         Handles incoming messages to initiate the redeem/unstaking process
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

        if (IStrategy(fr.strategy).isDirectStakeStrategy()) {
            IDeposit(address(this)).queueWithdraw(fr.strategy, fr.user, fr.amount);
        } else {
            IAllocation(address(this)).leave(fr.strategy, fr.user, fr.amount);
        }

        emit StakeRedeemReexecuted(fr.strategy, fr.user, fr.amount, id);
    }

    /* ========== ACL ========== */

    /// @inheritdoc ILockbox
    function setMailbox(address mailbox) external onlyVaultManager {
        require(
            mailbox != address(0) && mailbox.code.length > 0,
            InvalidMailbox(mailbox)
        );
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;

        emit MailboxUpdated(address(box.mailbox), mailbox);
        box.mailbox = IMailbox(mailbox);
    }

    /// @inheritdoc ILockbox
    function setDestination(uint32 destination) external onlyVaultManager {
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;

        emit DestinationUpdated(box.destination, destination);
        box.destination = destination;
    }

    /// @inheritdoc ILockbox
    function setLumiaFactory(address lumiaFactory) public onlyVaultManager {
        require(lumiaFactory != address(0), InvalidLumiaFactory(lumiaFactory));
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;

        emit LumiaFactoryUpdated(box.lumiaFactory, lumiaFactory);
        box.lumiaFactory = lumiaFactory;
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

        try IStrategy(strategy).isDirectStakeStrategy() returns (bool isDirect) {
            if (isDirect) {
                    // solhint-disable-next-line no-empty-blocks
                    try IDeposit(address(this)).queueWithdraw(strategy, user, stake) {
                        // success, nothing to do
                    } catch {
                        _storeFailedRedeem(strategy, user, stake);
                    }
                } else {
                    // solhint-disable-next-line no-empty-blocks
                    try IAllocation(address(this)).leave(strategy, user, stake) {
                        // success, nothing to do
                    } catch {
                        _storeFailedRedeem(strategy, user, stake);
                    }
                }
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
