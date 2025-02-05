// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ILockbox} from "../interfaces/ILockbox.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {IERC20, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MessageType, HyperlaneMailboxMessages} from "../libraries/HyperlaneMailboxMessages.sol";
import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../../external/hyperlane/libs/TypeCasts.sol";

import {LibHyperStaking, LockboxData} from "../libraries/LibHyperStaking.sol";

/**
 * @title LockboxFacet
 * @notice A customized version of XERC20Lockbox and Factory for handling interchain communication
 *         via Hyperlane Mailbox. Locks VaultTokens minted in Tier2 and mints tokens on the defined
 *         Lumia chain. Handles incoming messages to initiate the unstaking process
 * @dev Managed by HyperStaking Tier2 Vault and Vault Factory
 */
contract LockboxFacet is ILockbox, HyperStakingAcl {
    using HyperlaneMailboxMessages for bytes;
    using SafeERC20 for IERC20;

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
    function tokenDeployDispatch(
        address tokenAddress,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external payable diamondInternal {
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;
        require(box.lumiaFactory != address(0), RecipientUnset());

        bytes memory body = generateTokenDeployBody(tokenAddress, name, symbol, decimals);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(box.lumiaFactory);

        // msg.value should already include fee calculated
        box.mailbox.dispatch{value: msg.value}(box.destination, recipientBytes32, body);

        emit TokenDeployDispatched(
            address(box.mailbox),
            box.lumiaFactory,
            tokenAddress,
            name,
            symbol,
            decimals
        );
    }

    /// @inheritdoc ILockbox
    function bridgeTokenDispatch(
        address vaultToken,
        address user,
        uint256 shares
    ) external payable diamondInternal {
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;
        require(box.lumiaFactory != address(0), RecipientUnset());

        bytes memory body = generateTokenBridgeBody(vaultToken, user, shares);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(box.lumiaFactory);

        // msg.value should already include fee calculated
        box.mailbox.dispatch{value: msg.value}(box.destination, recipientBytes32, body);

        emit BridgeTokenDispatched(address(box.mailbox), box.lumiaFactory, vaultToken, user, shares);
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

        // parse message data (HyperlaneMailboxMessages)
        MessageType msgType = data.messageType();
        require(msgType == MessageType.TokenRedeem, UnsupportedMessage());

        _handleTokenRedeem(data);
    }

    /// @notice Handle specific TokenBridge message
    function _handleTokenRedeem(bytes calldata data) internal {
        address vaultToken = data.vaultToken();
        address user = data.sender(); // sender -> actual hyperstaking user
        uint256 shares = data.amount(); // amount -> amount of shares

        IERC4626(vaultToken).redeem(shares, user, address(this));
    }

    /* ========== ACL  ========== */

    /// @inheritdoc ILockbox
    function setMailbox(address mailbox) external onlyStrategyVaultManager {
        require(
            mailbox != address(0) && mailbox.code.length > 0,
            InvalidMailbox(mailbox)
        );
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;

        emit MailboxUpdated(address(box.mailbox), mailbox);
        box.mailbox = IMailbox(mailbox);
    }

    /// @inheritdoc ILockbox
    function setDestination(uint32 destination) external onlyStrategyVaultManager {
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;

        emit DestinationUpdated(box.destination, destination);
        box.destination = destination;
    }

    /// @inheritdoc ILockbox
    function setLumiaFactory(address lumiaFactory) public onlyStrategyVaultManager {
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
    function quoteDispatchTokenDeploy(
        address tokenAddress,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external view returns (uint256) {
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;
        return box.mailbox.quoteDispatch(
            box.destination,
            TypeCasts.addressToBytes32(box.lumiaFactory),
            generateTokenDeployBody(tokenAddress, name, symbol, decimals)
        );
    }

    /// @inheritdoc ILockbox
    function quoteDispatchTokenBridge(
        address vaultToken,
        address sender,
        uint256 shares
    ) external view returns (uint256) {
        LockboxData storage box = LibHyperStaking.diamondStorage().lockboxData;
        return box.mailbox.quoteDispatch(
            box.destination,
            TypeCasts.addressToBytes32(box.lumiaFactory),
            generateTokenBridgeBody(vaultToken, sender, shares)
        );
    }

    /// @inheritdoc ILockbox
    function quoteStakeDispatch(
        address strategy,
        address sender,
        uint256 allocation
    ) external view returns (uint256) {
        IERC4626 vaultToken = LibHyperStaking.diamondStorage().vaultTier2Info[strategy].vaultToken;

        // Vault: allocation -> shares
        uint256 shares = vaultToken.previewWithdraw(allocation);

        return this.quoteDispatchTokenBridge(
            address(vaultToken),
            sender,
            shares
        );
    }

    /// @inheritdoc ILockbox
    function generateTokenDeployBody(
        address tokenAddress,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public pure returns (bytes memory body) {
        body = HyperlaneMailboxMessages.serializeTokenDeploy(
            tokenAddress,
            name,
            symbol,
            decimals,
            bytes("") // no metadata
        );
    }

    /// @inheritdoc ILockbox
    function generateTokenBridgeBody(
        address vaultToken,
        address sender,
        uint256 shares
    ) public pure returns (bytes memory body) {
        body = HyperlaneMailboxMessages.serializeTokenBridge(
            vaultToken,
            sender,
            shares,
            bytes("") // no metadata
        );
    }
}
