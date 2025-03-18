// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IHyperlaneHandler} from "../interfaces/IHyperlaneHandler.sol";
import {IRealAssets} from "../interfaces/IRealAssets.sol";
import {LumiaDiamondAcl} from "../LumiaDiamondAcl.sol";

import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../../external/hyperlane/libs/TypeCasts.sol";
import {IMintableToken} from "../../external/3adao-lumia/interfaces/IMintableToken.sol";
import {IMintableTokenOwner} from "../../external/3adao-lumia/interfaces/IMintableTokenOwner.sol";

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

        // parse message type (HyperlaneMailboxMessages)
        MessageType msgType = data.messageType();

        // route message
        if (msgType == MessageType.RouteRegistry) {
            _handleRouteRegistry(originLockbox, origin, data);
            return;
        }

        if (msgType == MessageType.StakeInfo) {
            IRealAssets(address(this)).handleRwaMint(originLockbox, data);
            return;
        }

        if (msgType == MessageType.MigrationInfo) {
            _handleNewMigration(data);
            return;
        }

        revert UnsupportedMessage();
    }

    /// @inheritdoc IHyperlaneHandler
    function stakeRedeemDispatch(
        address strategy,
        address to,
        uint256 assetAmount
    ) external payable diamondInternal {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        RouteInfo storage r = ifs.routes[strategy];

        LibInterchainFactory.checkRoute(ifs, strategy);

        // burn rwaAsset
        r.rwaAsset.burn(assetAmount);

        bytes memory body = generateStakeRedeemBody(strategy, to, assetAmount);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(r.originLockbox);

        // msg.value should already include fee calculated
        ifs.mailbox.dispatch{value: msg.value}(r.originDestination, recipientBytes32, body);

        emit StakeRedeemDispatched(address(ifs.mailbox), r.originLockbox, strategy, to, assetAmount);
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
    function quoteDispatchStakeRedeem(
        address strategy,
        address to,
        uint256 assetAmount
    ) external view returns (uint256) {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        RouteInfo storage r = ifs.routes[strategy];

        return ifs.mailbox.quoteDispatch(
            r.originDestination,
            TypeCasts.addressToBytes32(r.originLockbox),
            generateStakeRedeemBody(strategy, to, assetAmount)
        );
    }

    /// @inheritdoc IHyperlaneHandler
    function generateStakeRedeemBody(
        address strategy,
        address to,
        uint256 assetAmount
    ) public pure returns (bytes memory body) {
        body = HyperlaneMailboxMessages.serializeStakeRedeem(
            strategy,
            to,
            assetAmount
        );
    }

    /// @inheritdoc IHyperlaneHandler
    function getRouteInfo(address strategy) external view returns (RouteInfo memory) {
        return LibInterchainFactory.diamondStorage().routes[strategy];
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Registers a route for rwa asset bridge
    /// @param originLockbox The address of the originating lockbox
    /// @param originDestination The origin destination chain ID
    /// @param data Encoded route-specific data
    function _handleRouteRegistry(
        address originLockbox,
        uint32 originDestination,
        bytes calldata data
    ) internal {
        address strategy = data.strategy(); // origin strategy address
        IMintableToken rwaAsset = IMintableToken(data.rwaAsset()); // rwaAsset

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        RouteInfo storage r = ifs.routes[strategy];
        require(r.exists == false, RouteAlreadyExist());

        LibInterchainFactory.checkRwaAsset(address(rwaAsset));

        IMintableTokenOwner rwaAssetOwner = IMintableTokenOwner(rwaAsset.owner());

        ifs.routes[strategy] = RouteInfo({
            exists: true,
            originDestination: originDestination,
            originLockbox: originLockbox,
            rwaAssetOwner: rwaAssetOwner,
            rwaAsset: rwaAsset
        });

        emit RouteRegistered(
            originLockbox,
            originDestination,
            strategy,
            address(rwaAssetOwner),
            address(rwaAsset)
        );
    }

    /// @notice Handle migration which happened on the origin chain
    /// @dev Adds opportunity to bridge out to a different strategy
    /// @param data Encoded route-specific data
    function _handleNewMigration(
        bytes calldata data
    ) internal {
        address fromStrategy = data.fromStrategy();
        address toStrategy = data.toStrategy();
        uint256 migrationAmount = data.migrationAmount();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        // both strategies and their routes should exist
        LibInterchainFactory.checkRoute(ifs, fromStrategy);
        LibInterchainFactory.checkRoute(ifs, toStrategy);

        require(
            ifs.routes[fromStrategy].rwaAsset == ifs.routes[toStrategy].rwaAsset,
            IncompatibleMigration()
        );

        // actual storage change
        ifs.generalBridgedState[fromStrategy] -= migrationAmount;
        ifs.generalBridgedState[toStrategy] += migrationAmount;

        emit MigrationAdded(
            fromStrategy,
            toStrategy,
            migrationAmount
        );
    }
}
