// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ILockbox} from "../interfaces/ILockbox.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {IERC20, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {HyperlaneMailboxMessages} from "../libraries/HyperlaneMailboxMessages.sol";
import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../../external/hyperlane/libs/TypeCasts.sol";

import {LibStrategyVault, LockboxData} from "../libraries/LibStrategyVault.sol";

/**
 * @title LockboxFacet
 * @notice A customized version of XERC20Lockbox and Factory for handling interchain communication
 *         via Hyperlane Mailbox. Locks VaultTokens minted in Tier2 and mints tokens on the defined
 *         Lumia chain. Handles incoming messages to initiate the unstaking process
 * @dev Managed by HyperStaking Tier2 Vault and Vault Factory
 */
contract LockboxFacet is ILockbox, HyperStakingAcl, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc ILockbox
    function tokenDeployDispatch(
        address tokenAddress,
        string memory name,
        string memory symbol
    ) external payable diamondInternal {
        LockboxData storage box = LibStrategyVault.diamondStorage().lockboxData;
        require(box.recipient != address(0), RecipientUnset());

        bytes memory body = generateTokenDeployBody(tokenAddress, name, symbol);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(box.recipient);

        // msg.value should already include fee calculated
        box.mailbox.dispatch{value: msg.value}(box.destination, recipientBytes32, body);

        emit TokenDeployDispatched(address(box.mailbox), box.recipient, tokenAddress, name, symbol);
    }

    /// @inheritdoc ILockbox
    function bridgeTokenDispatch(
        address vaultToken,
        address user,
        uint256 shares
    ) external payable diamondInternal {
        LockboxData storage box = LibStrategyVault.diamondStorage().lockboxData;
        require(box.recipient != address(0), RecipientUnset());

        bytes memory body = generateTokenBridgeBody(vaultToken, user, shares);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(box.recipient);

        // msg.value should already include fee calculated
        box.mailbox.dispatch{value: msg.value}(box.destination, recipientBytes32, body);

        emit BridgeTokenDispatched(address(box.mailbox), box.recipient, vaultToken, user, shares);
    }

    /* ========== ACL  ========== */

    /// @inheritdoc ILockbox
    function setMailbox(address mailbox) external onlyStrategyVaultManager nonReentrant {
        require(
            mailbox != address(0) && mailbox.code.length > 0,
            InvalidMailbox(mailbox)
        );
        LockboxData storage box = LibStrategyVault.diamondStorage().lockboxData;

        emit MailboxUpdated(address(box.mailbox), mailbox);
        box.mailbox = IMailbox(mailbox);
    }

    /// @inheritdoc ILockbox
    function setDestination(uint32 destination) external onlyStrategyVaultManager nonReentrant {
        LockboxData storage box = LibStrategyVault.diamondStorage().lockboxData;

        emit DestinationUpdated(box.destination, destination);
        box.destination = destination;
    }

    /// @inheritdoc ILockbox
    function setRecipient(address recipient) external onlyStrategyVaultManager nonReentrant {
        require(recipient != address(0), InvalidRecipient(recipient));
        LockboxData storage box = LibStrategyVault.diamondStorage().lockboxData;

        emit RecipientUpdated(box.recipient, recipient);
        box.recipient = recipient;
    }

    // ========= View ========= //

    /// @inheritdoc ILockbox
    function lockboxData() external view returns (LockboxData memory) {
        return LibStrategyVault.diamondStorage().lockboxData;
    }

    /// @inheritdoc ILockbox
    function quoteDispatchTokenDeploy(
        address tokenAddress,
        string memory name,
        string memory symbol
    ) external view returns (uint256) {
        LockboxData storage box = LibStrategyVault.diamondStorage().lockboxData;
        return box.mailbox.quoteDispatch(
            box.destination,
            TypeCasts.addressToBytes32(box.recipient),
            generateTokenDeployBody(tokenAddress, name, symbol)
        );
    }

    /// @inheritdoc ILockbox
    function quoteDispatchTokenBridge(
        address vaultToken,
        address sender,
        uint256 shares
    ) external view returns (uint256) {
        LockboxData storage box = LibStrategyVault.diamondStorage().lockboxData;
        return box.mailbox.quoteDispatch(
            box.destination,
            TypeCasts.addressToBytes32(box.recipient),
            generateTokenBridgeBody(vaultToken, sender, shares)
        );
    }

    /// @inheritdoc ILockbox
    function quoteStakeDispatch(
        address strategy,
        address sender,
        uint256 allocation
    ) external view returns (uint256) {
        IERC4626 vaultToken = LibStrategyVault.diamondStorage().vaultTier2Info[strategy].vaultToken;

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
        string memory symbol
    ) public pure returns (bytes memory body) {
        body = HyperlaneMailboxMessages.serializeTokenDeploy(
            tokenAddress,
            name,
            symbol,
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
