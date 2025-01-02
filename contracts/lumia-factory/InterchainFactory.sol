// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LumiaLPToken} from "./LumiaLPToken.sol";
import {IInterchainFactory} from "./interfaces/IInterchainFactory.sol";

import {IMailbox} from "../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../external/hyperlane/libs/TypeCasts.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
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
    using EnumerableMap for EnumerableMap.AddressToAddressMap;
    using HyperlaneMailboxMessages for bytes;

    /// Hyperlane Mailbox
    IMailbox public mailbox;

    /// ChainID - route destination to origin chain
    uint32 public destination;

    /// Address of the sender - Lockbox located on the origin chain
    address public originLockbox;

    address public lastSender;
    bytes public lastData;

    // Enumerable map storing the relation between origin vaultTokens and minted lpTokens
    EnumerableMap.AddressToAddressMap private tokensMap;

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
    ) external payable onlyMailbox {
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
            return;
        }

        if (msgType == MessageType.TokenDeploy) {
            _handleTokenDeploy(data_);
            return;
        }

        revert UnsupportedMessage();
    }

    /// @inheritdoc IInterchainFactory
    function redeemLpTokensDispatch(
        address vaultToken_,
        address spender_,
        uint256 shares_
    ) external payable {
        (bool exists, address lpToken) = tokensMap.tryGet(vaultToken_);
        require(exists, UnrecognizedVaultToken());

        // burn lpTokens
        LumiaLPToken(lpToken).burnFrom(spender_, shares_);

        bytes memory body = generateTokenRedeemBody(vaultToken_, spender_, shares_);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(originLockbox);

        // msg.value should already include fee calculated
        mailbox.dispatch{value: msg.value}(destination, recipientBytes32, body);

        emit RedeemTokenDispatched(address(mailbox), originLockbox, vaultToken_, spender_, shares_);
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
    function setDestination(uint32 destination_) external onlyOwner {
        emit DestinationUpdated(destination, destination_);
        destination = destination_;
    }

    /// @inheritdoc IInterchainFactory
    function setOriginLockbox(address newLockbox_) public onlyOwner {
        emit OriginLockboxUpdated(originLockbox, newLockbox_);
        originLockbox = newLockbox_;
    }

    // ========= View ========= //

    /// @inheritdoc IInterchainFactory
    function getLpToken(address vaultToken_) external view returns (address lpToken) {
        lpToken = tokensMap.get(vaultToken_);
    }

    /// @inheritdoc IInterchainFactory
    function tokensMapAt(uint256 index) external view returns (address key, address value) {
        (key, value) = tokensMap.at(index);
    }

    /// @inheritdoc IInterchainFactory
    function quoteDispatchTokenRedeem(
        address vaultToken_,
        address sender_,
        uint256 shares_
    ) external view returns (uint256) {
        return mailbox.quoteDispatch(
            destination,
            TypeCasts.addressToBytes32(originLockbox),
            generateTokenRedeemBody(vaultToken_, sender_, shares_)
        );
    }

    /// @inheritdoc IInterchainFactory
    function generateTokenRedeemBody(
        address vaultToken_,
        address sender_,
        uint256 shares_
    ) public pure returns (bytes memory body) {
        body = HyperlaneMailboxMessages.serializeTokenRedeem(
            vaultToken_,
            sender_,
            shares_,
            bytes("") // no metadata
        );
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Handle specific TokenDeploy message
    function _handleTokenDeploy(bytes calldata data_) internal {
        address tokenAddress = data_.tokenAddress(); // origin vault token address
        string memory name = data_.name();
        string memory symbol = data_.symbol();

        require(tokensMap.contains(tokenAddress) == false, TokenAlreadyDeployed());

        LumiaLPToken lpToken = new LumiaLPToken({
            interchainFactory_: address(this),
            name_: name,
            symbol_:symbol
        });

        // save in the storage # TODO
        tokensMap.set(tokenAddress, address(lpToken));

        emit TokenDeployed(tokenAddress, address(lpToken), name, symbol);
    }

    /// @notice Handle specific TokenBridge message
    function _handleTokenBridge(bytes calldata data_) internal {
        address vaultToken = data_.vaultToken();
        address sender = data_.sender();
        uint256 amount = data_.amount();

        // revert if key in not present in the map
        address lpToken = tokensMap.get(vaultToken);

        // mint LP tokens for the specified user
        LumiaLPToken(lpToken).mint(sender, amount);

        emit TokenBridged(vaultToken, lpToken, sender, amount);
    }
}
