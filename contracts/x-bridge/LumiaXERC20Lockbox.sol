// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {XERC20Lockbox} from "../external/defi-wonderland/contracts/XERC20Lockbox.sol";
import {IMailbox} from "../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../external/hyperlane/libs/TypeCasts.sol";

import {ReturnMessage} from "./libraries/ReturnMessage.sol";

/**
 * @title LumiaXERC20Lockbox
 * @notice XERC20Lockbox with added Hyperlane inter-chain functionalities and custom functions
 */
contract LumiaXERC20Lockbox is XERC20Lockbox, Ownable2Step {
    /// Hyperlane Mailbox
    IMailbox public mailbox;

    /// Contract which will get inter-chain message (ReturnMessage)
    address public recipient;

    /// chainID - route destination
    uint32 public destination;

    // ========= Errors ========= //

    // Custom error for failed ether transfers
    error RefundFailed(address recipient, uint256 amount);

    error InvalidMailbox(address badMailbox);
    error InvalidRecipient(address badRecipient);

    error RecipientUnset();

    // ========= Events ========= //

    event ReturnMessageSent(address indexed sender, uint256 amount);

    event MailboxUpdated(address indexed oldMailbox, address indexed newMailbox);
    event DestinationUpdated(uint32 indexed oldDestination, uint32 indexed newDestination);
    event RecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    /**
     * @param mailbox_ The address of the mailbox contract, used for cross-chain communication
     * @param destination_ Chain ID of the route destination for token return
     * @param xerc20_ The address of the cross-chain ERC20 token
     * @param erc20_ The address of the standard ERC20 token
     * @param isNative_ Native token (true) or a standard token (false)
     */
    constructor(
        address mailbox_,
        uint32 destination_,
        address xerc20_,
        address erc20_,
        bool isNative_
    ) XERC20Lockbox(xerc20_, erc20_, isNative_) Ownable(msg.sender) {
        setMailbox(mailbox_);
        setDestination(destination_);
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /**
     * @notice Dispatches a cross-chain message to initiate the return of tokens
     * @dev This function sends a message to trigger the token return process
     * @param amount_ Amount of tokens to return
     */
    function returnToken(uint256 amount_) external payable {
        require(recipient != address(0), RecipientUnset());

        // erc20 -> xerc20
        _deposit(address(this), amount_);

        // burn xerc20
        XERC20.burn(address(this), amount_);

        bytes memory body = generateBody(msg.sender, amount_);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(recipient);

        // quote message fee for forwarding a message across chains
        uint256 fee = mailbox.quoteDispatch(destination, recipientBytes32, body);

        mailbox.dispatch{value: fee}(destination, recipientBytes32, body);

        // Refund unused msg.value back to the recipient if it exceeds the required fee
        if (msg.value > fee) {
            uint256 refund = msg.value - fee;
            (bool success, ) = msg.sender.call{value: refund}("");
            require(success, RefundFailed(msg.sender, refund));
        }

        emit ReturnMessageSent(msg.sender, amount_);
    }

    // ========= View ========= //

    /// @notice Helper: separated function for getting mailbox dispatch quote
    function quoteDispatch(uint256 amount_) external view returns (uint256) {
        return mailbox.quoteDispatch(
            destination,
            TypeCasts.addressToBytes32(recipient),
            generateBody(msg.sender, amount_)
        );
    }

    /// @notice Helper: separated function for generating hyperlane message body
    function generateBody(address sender_, uint256 amount_) public pure returns (bytes memory body) {
        body = ReturnMessage.serialize(
            TypeCasts.addressToBytes32(sender_),
            amount_,
            bytes("") // no metadata
        );
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
     * @notice Updates the destination chain ID for the route
     * @param newDestination_ The new destination chain ID
     */
    function setDestination(uint32 newDestination_) public onlyOwner {
        emit DestinationUpdated(destination, newDestination_);
        destination = newDestination_;
    }

    /**
     * @notice Updates the recipient address for interchain messages
     * @param newRecipient_ The new recipient address
     */
    function setRecipient(address newRecipient_) public onlyOwner {
        require(newRecipient_ != address(0), InvalidRecipient(newRecipient_));
        emit RecipientUpdated(recipient, newRecipient_);
        recipient = newRecipient_;
    }
}
