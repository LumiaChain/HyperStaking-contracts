// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LumiaLPToken} from "../LumiaLPToken.sol";
import {IInterchainFactory} from "../interfaces/IInterchainFactory.sol";
import {LumiaDiamondAcl} from "../LumiaDiamondAcl.sol";

import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../../external/hyperlane/libs/TypeCasts.sol";

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {
    LibInterchainFactory, InterchainFactoryStorage, LastMessage
} from "../libraries/LibInterchainFactory.sol";

import {
    MessageType, HyperlaneMailboxMessages
} from "../../hyperstaking/libraries/HyperlaneMailboxMessages.sol";

/**
 * @title InterchainFactory
 * @notice Factory contract for LP tokens that operates based on messages received via Hyperlane
 * @dev Facilitates the deployment, management, and processing of LP token operations.
 */
contract InterchainFactoryFacet is IInterchainFactory, LumiaDiamondAcl {
    using EnumerableMap for EnumerableMap.AddressToAddressMap;
    using HyperlaneMailboxMessages for bytes;

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    /**
     * @param mailbox_ The address of the mailbox contract, used for cross-chain communication
     */
    // TODO proxy instead of owner
    // init function?
    // constructor(address mailbox_) Ownable(msg.sender) {
    //    setMailbox(mailbox_);
    // }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IInterchainFactory
    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata data
    ) external payable onlyMailbox {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        require(ifs.originLockbox != address(0), OriginLockboxNotSet());

        emit ReceivedMessage(origin, sender, msg.value, string(data));

        LastMessage memory lastMsg = LastMessage({
            sender: TypeCasts.bytes32ToAddress(sender),
            data: data
        });

        require(
            lastMsg.sender == address(ifs.originLockbox),
            NotFromLumiaLockbox(lastMsg.sender)
        );

        // save in the storage
        ifs.lastMessage = lastMsg;

        // parse message data (HyperlaneMailboxMessages)
        MessageType msgType = data.messageType();

        if (msgType == MessageType.TokenBridge) {
            _handleTokenBridge(data);
            return;
        }

        if (msgType == MessageType.TokenDeploy) {
            _handleTokenDeploy(data);
            return;
        }

        revert UnsupportedMessage();
    }

    /// @inheritdoc IInterchainFactory
    function redeemLpTokensDispatch(
        address vaultToken,
        address spender,
        uint256 shares
    ) external payable {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        (bool exists, address lpToken) = ifs.tokensMap.tryGet(vaultToken);
        require(exists, UnrecognizedVaultToken());

        // burn lpTokens
        LumiaLPToken(lpToken).burnFrom(spender, shares);

        bytes memory body = generateTokenRedeemBody(vaultToken, spender, shares);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(ifs.originLockbox);

        // msg.value should already include fee calculated
        ifs.mailbox.dispatch{value: msg.value}(ifs.destination, recipientBytes32, body);

        emit RedeemTokenDispatched(address(ifs.mailbox), ifs.originLockbox, vaultToken, spender, shares);
    }

    // ========= Owner ========= //

    /// @inheritdoc IInterchainFactory
    function setMailbox(address newMailbox) public onlyLumiaFactoryManager {
        require(
            newMailbox != address(0) && newMailbox.code.length > 0,
            InvalidMailbox(newMailbox)
        );

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        emit MailboxUpdated(address(ifs.mailbox), newMailbox);
        ifs.mailbox = IMailbox(newMailbox);
    }

    /// @inheritdoc IInterchainFactory
    function setDestination(uint32 newDestination) external onlyLumiaFactoryManager {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        emit DestinationUpdated(ifs.destination, newDestination);
        ifs.destination = newDestination;
    }

    /// @inheritdoc IInterchainFactory
    function setOriginLockbox(address newLockbox) public onlyLumiaFactoryManager {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        emit OriginLockboxUpdated(ifs.originLockbox, newLockbox);
        ifs.originLockbox = newLockbox;
    }

    // ========= View ========= //

    /// @inheritdoc IInterchainFactory
    function mailbox() external view returns(IMailbox) {
        return LibInterchainFactory.diamondStorage().mailbox;
    }

    /// @inheritdoc IInterchainFactory
    function destination() external view returns(uint32) {
        return LibInterchainFactory.diamondStorage().destination;
    }

    /// @inheritdoc IInterchainFactory
    function originLockbox() external view returns(address) {
        return LibInterchainFactory.diamondStorage().originLockbox;
    }

    /// @inheritdoc IInterchainFactory
    function lastMessage() external view returns(LastMessage memory) {
        return LibInterchainFactory.diamondStorage().lastMessage;
    }

    /// @inheritdoc IInterchainFactory
    function getLpToken(address vaultToken) external view returns (address lpToken) {
        lpToken = LibInterchainFactory.diamondStorage().tokensMap.get(vaultToken);
    }

    /// @inheritdoc IInterchainFactory
    function tokensMapAt(uint256 index) external view returns (address key, address value) {
        (key, value) = LibInterchainFactory.diamondStorage().tokensMap.at(index);
    }

    /// @inheritdoc IInterchainFactory
    function quoteDispatchTokenRedeem(
        address vaultToken,
        address sender,
        uint256 shares
    ) external view returns (uint256) {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        return ifs.mailbox.quoteDispatch(
            ifs.destination,
            TypeCasts.addressToBytes32(ifs.originLockbox),
            generateTokenRedeemBody(vaultToken, sender, shares)
        );
    }

    /// @inheritdoc IInterchainFactory
    function generateTokenRedeemBody(
        address vaultToken,
        address sender,
        uint256 shares
    ) public pure returns (bytes memory body) {
        body = HyperlaneMailboxMessages.serializeTokenRedeem(
            vaultToken,
            sender,
            shares,
            bytes("") // no metadata
        );
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Handle specific TokenDeploy message
    function _handleTokenDeploy(bytes calldata data) internal {
        address tokenAddress = data.tokenAddress(); // origin vault token address
        string memory name = data.name();
        string memory symbol = data.symbol();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        require(ifs.tokensMap.contains(tokenAddress) == false, TokenAlreadyDeployed());

        address lpToken = address(new LumiaLPToken(address(this), name, symbol));

        ifs.tokensMap.set(tokenAddress, lpToken);

        emit TokenDeployed(tokenAddress, lpToken, name, symbol);
    }

    /// @notice Handle specific TokenBridge message
    function _handleTokenBridge(bytes calldata data) internal {
        address vaultToken = data.vaultToken();
        address sender = data.sender();
        uint256 amount = data.amount();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        // revert if key in not present in the map
        address lpToken = ifs.tokensMap.get(vaultToken);

        // mint LP tokens for the specified user
        LumiaLPToken(lpToken).mint(sender, amount);

        emit TokenBridged(vaultToken, lpToken, sender, amount);
    }
}
