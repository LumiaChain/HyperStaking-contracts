// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LumiaLPToken} from "../LumiaLPToken.sol";
import {IInterchainFactory} from "../interfaces/IInterchainFactory.sol";
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
 * @title InterchainFactory
 * @notice Factory contract for LP tokens that operates based on messages received via Hyperlane
 * @dev Facilitates the deployment, management, and processing of LP token operations
 */
contract InterchainFactoryFacet is IInterchainFactory, LumiaDiamondAcl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using HyperlaneMailboxMessages for bytes;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IInterchainFactory
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
            _handleTokenBridge(data);
            return;
        }

        if (msgType == MessageType.TokenDeploy) {
            _handleTokenDeploy(originLockbox, origin, data);
            return;
        }

        revert UnsupportedMessage();
    }

    /// @inheritdoc IInterchainFactory
    function redeemLpTokensDispatch(
        address strategy,
        address user,
        uint256 shares
    ) external payable {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        require(_routeExists(ifs, strategy), RouteDoesNotExist(strategy));

        RouteInfo storage r = ifs.routes[strategy];

        // burn lpTokens
        r.lpToken.burnFrom(user, shares);

        bytes memory body = generateTokenRedeemBody(strategy, user, shares);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(r.originLockbox);

        // msg.value should already include fee calculated
        ifs.mailbox.dispatch{value: msg.value}(r.originDestination, recipientBytes32, body);

        emit RedeemTokenDispatched(address(ifs.mailbox), r.originLockbox, strategy, user, shares);
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

    /// @inheritdoc IInterchainFactory
    function mailbox() external view returns(IMailbox) {
        return LibInterchainFactory.diamondStorage().mailbox;
    }

    /// @inheritdoc IInterchainFactory
    function destination(address originLockbox) external view returns(uint32) {
        return LibInterchainFactory.diamondStorage().destinations[originLockbox];
    }

    /// @inheritdoc IInterchainFactory
    function lastMessage() external view returns(LastMessage memory) {
        return LibInterchainFactory.diamondStorage().lastMessage;
    }

    /// @inheritdoc IInterchainFactory
    function getLpToken(address strategy) external view returns (LumiaLPToken) {
        return LibInterchainFactory.diamondStorage().routes[strategy].lpToken;
    }

    /// @inheritdoc IInterchainFactory
    function getRouteInfo(address strategy) external view returns (RouteInfo memory) {
        return LibInterchainFactory.diamondStorage().routes[strategy];
    }

    /// @inheritdoc IInterchainFactory
    function quoteDispatchTokenRedeem(
        address strategy,
        address sender,
        uint256 shares
    ) external view returns (uint256) {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        require(_routeExists(ifs, strategy), RouteDoesNotExist(strategy));

        RouteInfo storage r = ifs.routes[strategy];

        return ifs.mailbox.quoteDispatch(
            r.originDestination,
            TypeCasts.addressToBytes32(r.originLockbox),
            generateTokenRedeemBody(strategy, sender, shares)
        );
    }

    /// @inheritdoc IInterchainFactory
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

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Handle specific TokenDeploy message
    function _handleTokenDeploy(
        address originLockbox,
        uint32 originDestination,
        bytes calldata data
    ) internal {
        address strategy = data.strategy(); // origin strategy address
        string memory name = data.name();
        string memory symbol = data.symbol();
        uint8 decimals = data.decimals();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        require(_routeExists(ifs, strategy) == false, RouteAlreadyExist());

        LumiaLPToken lpToken = new LumiaLPToken(address(this), name, symbol, decimals);
        // TODO create Vault

        ifs.routes[strategy] = RouteInfo({
            exists: true,
            originLockbox: originLockbox,
            originDestination: originDestination,
            lpToken: lpToken
            // lendingVault TODO
        });

        emit TokenDeployed(strategy, address(lpToken), name, symbol, decimals);
    }

    /// @notice Handle specific TokenBridge message
    function _handleTokenBridge(bytes calldata data) internal {
        address strategy = data.strategy();
        address sender = data.sender();
        uint256 sharesAmount = data.sharesAmount();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        // revert if route not exists
        require(_routeExists(ifs, strategy), RouteDoesNotExist(strategy));

        RouteInfo storage r = ifs.routes[strategy];

        // mint LP tokens for the specified user
        r.lpToken.mint(sender, sharesAmount);

        emit TokenBridged(strategy, address(r.lpToken), sender, sharesAmount);
    }

    /// @notice Checks whether route exists
    function _routeExists(
        InterchainFactoryStorage storage ifs,
        address strategy
    ) internal view returns (bool){
        return ifs.routes[strategy].exists;
    }
}
