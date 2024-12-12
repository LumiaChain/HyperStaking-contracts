// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LockboxData} from "../libraries/LibStrategyVault.sol";

/**
 * @title ILockbox
 * @dev Interface for LockboxFacet
 */
interface ILockbox {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event TokenDeployDispatched(
        address indexed mailbox,
        address recipient,
        address tokenAddress,
        string name,
        string symbol
    );

    event BridgeTokenDispatched(
        address indexed mailbox,
        address recipient,
        address indexed vaultToken,
        address indexed user,
        uint256 shares
    );

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
     * @notice Dispatches a cross-chain message responsible for minting corresponding lp token
     * @dev This function sends a message to trigger the token deploy
     */
    function tokenDeployDispatch(
        address tokenAddress,
        string memory name,
        string memory symbol
    ) external payable;

    /**
     * @notice Dispatches a cross-chain message responsible for bridiging vault token
     * @dev This function sends a message to trigger the token mint process
     */
    function bridgeTokenDispatch(
        address vaultToken,
        address user,
        uint256 shares
    ) external payable;

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
    function quoteDispatchTokenDeploy(
        address tokenAddress,
        string memory name,
        string memory symbol
    ) external view returns (uint256);

    /// @notice Helper: separated function for getting mailbox dispatch quote
    function quoteDispatchTokenBridge(
        address vaultToken,
        address sender,
        uint256 shares
    ) external view returns (uint256);

    /// @notice Helper: mailbox dispatch quote, but using stake data
    /// @dev Externally only for estimation purposes, as the amount of shares
    ///      based on allocation changes depending on the allocation of the Vault.
    function quoteStakeDispatch(
        address strategy,
        address sender,
        uint256 allocation
    ) external view returns (uint256);

    /// @notice Helper: separated function for generating hyperlane message body
    function generateTokenDeployBody(
        address tokenAddress,
        string memory name,
        string memory symbol
    ) external pure returns (bytes memory body);

    /// @notice Helper: separated function for generating hyperlane message body
    function generateTokenBridgeBody(
        address vaultToken,
        address sender,
        uint256 shares
    ) external pure returns (bytes memory body);
}
