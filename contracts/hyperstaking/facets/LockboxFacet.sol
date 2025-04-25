// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ILockbox} from "../interfaces/ILockbox.sol";
import {IDeposit} from "../interfaces/IDeposit.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {MessageType, HyperlaneMailboxMessages} from "../libraries/HyperlaneMailboxMessages.sol";
import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../../external/hyperlane/libs/TypeCasts.sol";

import {LibHyperStaking, LockboxData} from "../libraries/LibHyperStaking.sol";

/**
 * @title LockboxFacet
 * @notice A customized version of XERC20Lockbox and Factory for handling interchain communication
 *         via Hyperlane Mailbox. Locks DirectStake or VaultTokens minted in Tier2 and mints tokens
 *         on the Lumia chain. Handles incoming messages to initiate the redeem/unstaking process
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
    function migrationInfoDispatch(
        address fromStrategy,
        address toStrategy,
        uint256 migrationAmount
    ) external payable diamondInternal {
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;
        // require(box.lumiaFactory != address(0), RecipientUnset());

        bytes memory body = generateMigrationInfoBody(fromStrategy, toStrategy, migrationAmount);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(box.lumiaFactory);

        // msg.value should already include fee calculated
        box.mailbox.dispatch{value: msg.value}(box.destination, recipientBytes32, body);

        emit MigrationInfoDispatched(
            address(box.mailbox),
            box.lumiaFactory,
            fromStrategy,
            toStrategy,
            migrationAmount
        );
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

    /// @inheritdoc ILockbox
    function quoteDispatchMigrationInfo(
        address fromStrategy,
        address toStrategy,
        uint256 migrationAmount
    ) external view returns (uint256) {
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;
        return box.mailbox.quoteDispatch(
            box.destination,
            TypeCasts.addressToBytes32(box.lumiaFactory),
            generateMigrationInfoBody(fromStrategy, toStrategy, migrationAmount)
        );
    }

    /// @inheritdoc ILockbox
    function generateMigrationInfoBody(
        address fromStrategy,
        address toStrategy,
        uint256 migrationAmount
    ) public pure returns (bytes memory body) {
        body = HyperlaneMailboxMessages.serializeMigrationInfo(
            fromStrategy,
            toStrategy,
            migrationAmount
        );
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
            IDeposit(address(this)).directStakeWithdraw(strategy, stake, user);
        } else {
            IDeposit(address(this)).stakeWithdrawTier2(strategy, stake, user);
        }
    }
}
