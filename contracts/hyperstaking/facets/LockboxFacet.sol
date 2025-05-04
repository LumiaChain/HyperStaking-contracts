// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ILockbox} from "../interfaces/ILockbox.sol";
import {IDeposit} from "../interfaces/IDeposit.sol";
import {IAllocation} from "../interfaces/IAllocation.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {IStakeInfoRoute} from "../interfaces/IStakeInfoRoute.sol";

import {
    StakeInfoData, MessageType, HyperlaneMailboxMessages
} from "../libraries/HyperlaneMailboxMessages.sol";
import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../../external/hyperlane/libs/TypeCasts.sol";

import {LibHyperStaking, LockboxData} from "../libraries/LibHyperStaking.sol";

/**
 * @title LockboxFacet
 * @notice A customized version of XERC20Lockbox and Factory for handling interchain communication
 *         via Hyperlane Mailbox. Locks DirectStake assets or VaultTokens shares
 *         Handles incoming messages to initiate the redeem/unstaking process
 */
contract LockboxFacet is ILockbox, HyperStakingAcl {
    using HyperlaneMailboxMessages for bytes;

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

        // quote message fee for forwarding a TokenBridge message across chains
        uint256 fee = IStakeInfoRoute(address(this)).quoteDispatchStakeInfo(data);

        // actual dispatch
        IStakeInfoRoute(address(this)).stakeInfoDispatch{value: fee}(data);
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

    /* ========== ACL  ========== */

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

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Handle specific StakeRedeem message
    function _handleStakeRedeem(bytes calldata data) internal {
        address strategy = data.strategy();
        address user = data.sender(); // sender -> actual hyperstaking user
        uint256 stake = data.redeemAmount(); // amount -> amount of rwa asset / stake

        if (IStrategy(strategy).isDirectStakeStrategy()) {
            IDeposit(address(this)).stakeWithdraw(strategy, user, stake);
        } else {
            uint256 allocation = IStrategy(strategy).previewAllocation(stake);
            IAllocation(address(this)).leave(strategy, user, allocation);
        }
    }
}
