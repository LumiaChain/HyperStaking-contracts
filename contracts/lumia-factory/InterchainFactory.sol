// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LumiaLPToken} from "./LumiaLPToken.sol";
import {IInterchainFactory} from "./interfaces/IInterchainFactory.sol";

import {IMailbox} from "../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../external/hyperlane/libs/TypeCasts.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    MessageType, HyperlaneMailboxMessages
} from "../hyperstaking/libraries/HyperlaneMailboxMessages.sol";

/**
 * @title InterchainFactory
 * @notice Factory contract for LP tokens that operates based on messages received via Hyperlane
 * @dev Facilitates the deployment, management, and processing of LP token operations.
 * #TODO Diamond Proxy 2
 */
contract InterchainFactory is IInterchainFactory, Ownable {
    using HyperlaneMailboxMessages for bytes;

    /// Hyperlane Mailbox
    IMailbox public mailbox;

    /// Address of the sender - Lockbox located on the origin chain
    address public originLockbox;

    address public lastSender;
    bytes public lastData;

    // TODO enumerable map
    mapping(address originToken => LumiaLPToken lpToken) public lpTokens;

    // ========= Events ========= //

    // ========= Errors ========= //

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
    // TODO proxy instead of owner
    constructor(address mailbox_) Ownable(msg.sender) {
        setMailbox(mailbox_);
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IInterchainFactory
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

        // parse message data (HyperlaneMailboxMessages)
        MessageType msgType = data_.messageType();

        if (msgType == MessageType.TokenBridge) {
            _handleTokenBridge(data_);
        }

        if (msgType == MessageType.TokenDeploy) {
            _handleTokenDeploy(data_);
        }
    }

    // ========= Owner ========= //

    /// @inheritdoc IInterchainFactory
    function setMailbox(address newMailbox_) public onlyOwner {
        require(
            newMailbox_ != address(0) && newMailbox_.code.length > 0,
            InvalidMailbox(newMailbox_)
        );

        emit MailboxUpdated(address(mailbox), newMailbox_);
        mailbox = IMailbox(newMailbox_);
    }

    /// @inheritdoc IInterchainFactory
    function setOriginLockbox(address newLockbox_) public onlyOwner {
        emit OriginLockboxUpdated(originLockbox, newLockbox_);
        originLockbox = newLockbox_;
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    function _handleTokenDeploy(bytes calldata data_) internal {
        address tokenAddress = data_.tokenAddress();
        string memory name = data_.name();
        string memory symbol = data_.symbol();

        require(address(lpTokens[tokenAddress]) == address(0), TokenAlreadyDeployed());

        LumiaLPToken lpToken = new LumiaLPToken({
            interchainFactory_: address(this),
            name_: name,
            symbol_:symbol
        });

        // save in the storage
        lpTokens[tokenAddress] = lpToken;

        emit TokenDeployed(tokenAddress, address(lpToken), name, symbol);
    }

    function _handleTokenBridge(bytes calldata data_) internal {
        address vaultToken = data_.vaultToken();
        address sender = data_.sender();
        uint256 amount = data_.amount();

        LumiaLPToken lpToken = lpTokens[vaultToken];

        // mint LP tokens for the specified used
        lpToken.mint(sender, amount);

        emit TokenBridged(vaultToken, address(lpToken), sender, amount);
    }
}
