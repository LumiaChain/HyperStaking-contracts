// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IHyperlaneHandler} from "../interfaces/IHyperlaneHandler.sol";
import {IRouteFactory} from "../interfaces/IRouteFactory.sol";
import {LumiaDiamondAcl} from "../LumiaDiamondAcl.sol";

import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../../external/hyperlane/libs/TypeCasts.sol";

import {
    LibInterchainFactory, InterchainFactoryStorage, RouteInfo, LastMessage, EnumerableSet
} from "../libraries/LibInterchainFactory.sol";

import {
    MessageType, HyperlaneMailboxMessages
} from "../../hyperstaking/libraries/HyperlaneMailboxMessages.sol";

/**
 * @title HyperlaneHandlerFacet
 * @notice Handles interchain messaging via Hyperlane for LP token operations
 */
contract HyperlaneHandlerFacet is IHyperlaneHandler, LumiaDiamondAcl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using HyperlaneMailboxMessages for bytes;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IHyperlaneHandler
    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata data
    ) external payable onlyMailbox {
        emit ReceivedMessage(origin, sender, msg.value, string(data));

        // parse sender, store lastMsg
        address originLockbox = TypeCasts.bytes32ToAddress(sender);
        LastMessage memory lastMsg = LastMessage({
            sender: originLockbox,
            data: data
        });

        // save in the storage
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        ifs.lastMessage = lastMsg;

        // ---

        require(
            ifs.authorizedOrigins.contains(originLockbox),
            NotFromHyperStaking(originLockbox)
        );

        require(origin == ifs.destinations[originLockbox], BadOriginDestination(origin));

        // parse message data (HyperlaneMailboxMessages)
        MessageType msgType = data.messageType();

        if (msgType == MessageType.TokenBridge) {
            IRouteFactory(address(this)).handleTokenBridge(data);
            return;
        }

        if (msgType == MessageType.TokenDeploy) {
            IRouteFactory(address(this)).handleTokenDeploy(originLockbox, origin, data);
            return;
        }

        revert UnsupportedMessage();
    }

    /// @inheritdoc IHyperlaneHandler
    function redeemLpTokensDispatch(
        address strategy,
        address user,
        uint256 shares
    ) external payable { // TODO diamondInternal
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        RouteInfo storage r = ifs.routes[strategy];
        require(r.exists == true, RouteDoesNotExist(strategy));

        // burn lpTokens
        r.lpToken.burnFrom(user, shares);

        bytes memory body = generateTokenRedeemBody(strategy, user, shares);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(r.originLockbox);

        // msg.value should already include fee calculated
        ifs.mailbox.dispatch{value: msg.value}(r.originDestination, recipientBytes32, body);

        emit RedeemTokenDispatched(address(ifs.mailbox), r.originLockbox, strategy, user, shares);
    }

    // ========= Restricted ========= //

    /// @inheritdoc IHyperlaneHandler
    function setMailbox(address newMailbox) external onlyLumiaFactoryManager {
        require(
            newMailbox != address(0) && newMailbox.code.length > 0,
            InvalidMailbox(newMailbox)
        );

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        emit MailboxUpdated(address(ifs.mailbox), newMailbox);
        ifs.mailbox = IMailbox(newMailbox);
    }

    /// @inheritdoc IHyperlaneHandler
    function updateAuthorizedOrigin(
        address originLockbox,
        bool authorized,
        uint32 originDestination
    ) external onlyLumiaFactoryManager {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        require(originLockbox != address(0), OriginUpdateFailed());

        if (authorized) {
            // EnumerableSet returns a boolean indicating success
            require(ifs.authorizedOrigins.add(originLockbox), OriginUpdateFailed());
            ifs.destinations[originLockbox] = originDestination;
        } else {
            require(ifs.authorizedOrigins.remove(originLockbox), OriginUpdateFailed());
            delete ifs.destinations[originLockbox];
        }

        emit AuthorizedOriginUpdated(originLockbox, authorized, originDestination);
    }

    // ========= View ========= //

    /// @inheritdoc IHyperlaneHandler
    function mailbox() external view returns(IMailbox) {
        return LibInterchainFactory.diamondStorage().mailbox;
    }

    /// @inheritdoc IHyperlaneHandler
    function destination(address originLockbox) external view returns(uint32) {
        return LibInterchainFactory.diamondStorage().destinations[originLockbox];
    }

    /// @inheritdoc IHyperlaneHandler
    function lastMessage() external view returns(LastMessage memory) {
        return LibInterchainFactory.diamondStorage().lastMessage;
    }

    /// @inheritdoc IHyperlaneHandler
    function quoteDispatchTokenRedeem(
        address strategy,
        address sender,
        uint256 shares
    ) external view returns (uint256) {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        RouteInfo storage r = ifs.routes[strategy];

        return ifs.mailbox.quoteDispatch(
            r.originDestination,
            TypeCasts.addressToBytes32(r.originLockbox),
            generateTokenRedeemBody(strategy, sender, shares)
        );
    }

    /// @inheritdoc IHyperlaneHandler
    function generateTokenRedeemBody(
        address strategy,
        address sender,
        uint256 shares
    ) public pure returns (bytes memory body) {
        body = HyperlaneMailboxMessages.serializeTokenRedeem(
            strategy,
            sender,
            shares,
            bytes("") // no metadata
        );
    }
}
