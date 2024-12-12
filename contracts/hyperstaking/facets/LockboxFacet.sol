// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ILockbox} from "../interfaces/ILockbox.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {IERC20, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {BridgeTokenMessage} from "../libraries/BridgeTokenMessage.sol";
import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {TypeCasts} from "../../external/hyperlane/libs/TypeCasts.sol";

import {LibStrategyVault, VaultTier2, LockboxData} from "../libraries/LibStrategyVault.sol";

/**
 * @title LockboxFacet
 * @notice A simplified, customized version of XERC20Lockbox for handling interchain communication
 *         via Hyperlane Mailbox. Locks VaultTokens minted in Tier2 and mints tokens on the defined
 *         Lumia chain. Handles incoming messages to initiate the unstaking process
 * @dev Managed by HyperStaking Tier2 Vault
 */
contract LockboxFacet is ILockbox, HyperStakingAcl, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    modifier onlyVaultToken(address strategy) {
        VaultTier2 storage t = LibStrategyVault.diamondStorage().vaultTier2Info[strategy];
        require(msg.sender == address(t.vaultToken), InvalidVaultToken(msg.sender));
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc ILockbox
    function bridgeToken(
        address vaultToken,
        address user,
        uint256 amount
    ) external payable diamondInternal {
        LockboxData storage box = LibStrategyVault.diamondStorage().lockboxData;
        require(box.recipient != address(0), RecipientUnset());

        bytes memory body = generateBody(vaultToken, user, amount);

        // address left-padded to bytes32 for compatibility with hyperlane
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(box.recipient);

        // quote message fee for forwarding a message across chains
        // uint256 fee = quoteDispatch(address(vaultToken), user, amount);
        box.mailbox.dispatch{value: msg.value}(box.destination, recipientBytes32, body);

        emit VaultTokenBridged(address(vaultToken), user, amount);
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
    function quoteDispatch(
        address vaultToken,
        address sender,
        uint256 amount
    ) public view returns (uint256) {
        LockboxData storage box = LibStrategyVault.diamondStorage().lockboxData;
        return box.mailbox.quoteDispatch(
            box.destination,
            TypeCasts.addressToBytes32(box.recipient),
            generateBody(vaultToken, sender, amount)
        );
    }

    /// @inheritdoc ILockbox
    function generateBody(
        address vaultToken,
        address sender,
        uint256 amount
    ) public pure returns (bytes memory body) {
        body = BridgeTokenMessage.serialize(
            TypeCasts.addressToBytes32(vaultToken),
            TypeCasts.addressToBytes32(sender),
            amount,
            bytes("") // no metadata
        );
    }
}
