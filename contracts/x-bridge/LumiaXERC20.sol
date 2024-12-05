// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {XERC20} from "../external/defi-wonderland/contracts/XERC20.sol";

import {IMailbox} from "../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../external/hyperlane/libs/TypeCasts.sol";

import {ReturnMessage} from "./libraries/ReturnMessage.sol";
import {ILumiaReceiver} from "./interfaces/ILumiaReceiver.sol";

/**
 * @title LumiaXERC20
 * @notice Hyperlane version of XERC20 with custom handle for inter-chain ReturnMessage
 */
contract LumiaXERC20 is XERC20 {
    using ReturnMessage for bytes;

    /// Hyperlane Mailbox
    IMailbox public mailbox;

    /// Address of the origin chain sender - LumiaERC20Lockbox
    address public originLockbox;

    /// Actual of the contract which should receive message (ReceivedMessage)
    ILumiaReceiver public lumiaReceiver;

    address public lastSender;
    bytes public lastData;

    // ========= Errors ========= //

    error NotFromMailbox(address from);
    error NotFromLumiaLockbox(address sender);

    error OriginLockboxNotSet();
    error LumiaReceiverNotSet();

    error InvalidMailbox(address badMailbox);
    error InvalidLumiaReceiver(address badReceiver);


    // ========= Events ========= //

    event ReceivedMessage(
        uint32 indexed origin,
        bytes32 indexed sender,
        uint256 value,
        string message
    );
    event ReturnMessageReceived(address indexed sender, uint256 returnedAmount);

    event MailboxUpdated(address indexed oldMailbox, address indexed newMailbox);
    event OriginLockboxUpdated(address indexed oldLockbox, address indexed newLockbox);
    event LumiaReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);

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
     * @param name_ The name of XERC20 token
     * @param symbol_ The symbol of XERC20 token
     */
    constructor(
        address mailbox_,
        string memory name_,
        string memory symbol_
    ) XERC20(name_, symbol_, msg.sender) {
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
        require(address(lumiaReceiver) != address(0), LumiaReceiverNotSet());

        emit ReceivedMessage(origin_, sender_, msg.value, string(data_));

        lastSender = TypeCasts.bytes32ToAddress(sender_);
        lastData = data_;

        require(
            lastSender == address(originLockbox),
            NotFromLumiaLockbox(lastSender)
        );

        // parse data_ (ReturnMessage)
        address returnSender = TypeCasts.bytes32ToAddress(data_.returnSender());
        uint256 returnAmount = data_.returnAmount();

        lumiaReceiver.tokensReceived(returnAmount);

        emit ReturnMessageReceived(returnSender, returnAmount);
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

    /**
     * @notice Updates the Lumia receiver address
     * @param newReceiver_ The new Lumia receiver address
     */
    function setLumiaReceiver(address newReceiver_) public onlyOwner {
        require(
            newReceiver_ != address(0) && newReceiver_.code.length > 0,
            InvalidLumiaReceiver(newReceiver_)
        );

        emit LumiaReceiverUpdated(address(lumiaReceiver), newReceiver_);
        lumiaReceiver = ILumiaReceiver(newReceiver_);
    }
}
