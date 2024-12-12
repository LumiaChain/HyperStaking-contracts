// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LockboxData} from "../libraries/LibStrategyVault.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title ILockbox
 * @dev Interface for LockboxFacet
 */
interface ILockbox {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event VaultTokenBridged(address indexed vaultToken, address indexed user, uint256 amount);

    event MailboxUpdated(address indexed oldMailbox, address indexed newMailbox);
    event DestinationUpdated(uint32 indexed oldDestination, uint32 indexed newDestination);
    event RecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    //===========================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error InvalidVaultToken(address badVaultToken);
    error InvalidMailbox(address badMailbox);
    error InvalidRecipient(address badRecipient);

    error RecipientUnset();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Dispatches a cross-chain message responsible for bridiging vault token
     * @dev This function sends a message to trigger the token return process
     * @param amount Amount of tokens to bridge
     */
    function bridgeToken(address vaultToken, address user, uint256 amount) external payable;

    /**
     * @notice Updates the mailbox address used for interchain messaging
     * @param mailbox The new mailbox address
     */
    function setMailbox(address mailbox) external;

    /**
     * @notice Updates the destination chain ID for the route
     * @param destination The new destination chain ID
     */
    function setDestination(uint32 destination) external;

    /**
     * @notice Updates the recipient contract address for mailbox messages
     * @param recipient The new recipient address
     */
    function setRecipient(address recipient) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Returns Lockbox data, including mailbox address, destination, and recipient address
    function lockboxData() external view returns (LockboxData memory);

    /// @notice Helper: separated function for getting mailbox dispatch quote
    function quoteDispatch(
        address vaultToken,
        address sender,
        uint256 amount
    ) external view returns (uint256);

    /// @notice Helper: separated function for generating hyperlane message body
    function generateBody(
        address vaultToken,
        address sender,
        uint256 amount
    ) external pure returns (bytes memory body);
}
