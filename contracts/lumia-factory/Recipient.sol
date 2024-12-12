// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IMailbox} from "../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../external/hyperlane/libs/TypeCasts.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BridgeTokenMessage} from "../hyperstaking/libraries/BridgeTokenMessage.sol";

import "hardhat/console.sol";

/**
 * @title TODO
 * @notice Recipient - factory of LP tokens
 */
contract Recipient is Ownable {
    using BridgeTokenMessage for bytes;

    /// Hyperlane Mailbox
    IMailbox public mailbox;

    /// Address of the sender - Lockbox located in the origin chain
    address public originLockbox;

    address public lastSender;
    bytes public lastData;

    // ========= Events ========= //

    event ReceivedMessage(
        uint32 indexed origin,
        bytes32 indexed sender,
        uint256 value,
        string message
    );

    // TODO 2 messages
    event MessageReceived(address indexed sender, uint256 amount);

    event MailboxUpdated(address indexed oldMailbox, address indexed newMailbox);
    event OriginLockboxUpdated(address indexed oldLockbox, address indexed newLockbox);

    // ========= Errors ========= //

    error NotFromMailbox(address from);
    error NotFromLumiaLockbox(address sender);

    error OriginLockboxNotSet();
    error LumiaReceiverNotSet();

    error InvalidMailbox(address badMailbox);
    error InvalidLumiaReceiver(address badReceiver);

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    /// @notice Only accept messages from an Hyperlane Mailbox contract
    modifier onlyMailbox() {
        require(
            msg.sender == address(mailbox),
            NotFromMailbox(msg.sender)
        );
        _;
    }

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    /**
     * @param mailbox_ The address of the mailbox contract, used for cross-chain communication
     */
    constructor(address mailbox_) Ownable(msg.sender) {
        setMailbox(mailbox_);
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /**
     * @notice Function called by the Mailbox contract when a message is received
     */
    function handle(
        uint32 origin_,
        bytes32 sender_,
        bytes calldata data_
    ) external payable {
        require(originLockbox != address(0), OriginLockboxNotSet());

        emit ReceivedMessage(origin_, sender_, msg.value, string(data_));

        lastSender = TypeCasts.bytes32ToAddress(sender_);
        lastData = data_;

        require(
            lastSender == address(originLockbox),
            NotFromLumiaLockbox(lastSender)
        );

        // parse data_ (BridgeTokenMessage ? TODO)
        address msgVaultToken = TypeCasts.bytes32ToAddress(data_.vaultToken());
        address msgSender = TypeCasts.bytes32ToAddress(data_.sender());
        uint256 msgAmount = data_.amount();

        console.log("msgVaultToken:", msgVaultToken);
        console.log("msgSender:", msgSender);
        console.log("msgAmount:", msgAmount);

        emit MessageReceived(msgSender, msgAmount); // TODO
    }

    // ========= Owner ========= //

    /**
     * @notice Updates the mailbox address used for interchain messaging
     * @param newMailbox_ The new mailbox address
     */
    function setMailbox(address newMailbox_) public onlyOwner {
        require(
            newMailbox_ != address(0) && newMailbox_.code.length > 0,
            InvalidMailbox(newMailbox_)
        );

        emit MailboxUpdated(address(mailbox), newMailbox_);
        mailbox = IMailbox(newMailbox_);
    }

    /**
     * @notice Updates the origin lockbox address
     * @param newLockbox_ The new origin lockbox address
     */
    function setOriginLockbox(address newLockbox_) public onlyOwner {
        emit OriginLockboxUpdated(originLockbox, newLockbox_);
        originLockbox = newLockbox_;
    }
}
