// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LockboxData} from "../libraries/LibHyperStaking.sol";

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
        address lumiaFactory,
        address tokenAddress,
        string name,
        string symbol,
        uint8 decimals
    );

    event BridgeTokenDispatched(
        address indexed mailbox,
        address lumiaFactory,
        address indexed vaultToken,
        address indexed user,
        uint256 shares
    );

    event ReceivedMessage(
        uint32 indexed origin,
        bytes32 indexed sender,
        uint256 value,
        string message
    );

    event MailboxUpdated(address indexed oldMailbox, address indexed newMailbox);
    event DestinationUpdated(uint32 indexed oldDestination, uint32 indexed newDestination);
    event LumiaFactoryUpdated(address indexed oldLumiaFactory, address indexed newLumiaFactory);

    //===========================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error InvalidVaultToken(address badVaultToken);
    error InvalidMailbox(address badMailbox);
    error InvalidLumiaFactory(address badLumiaFactory);

    error RecipientUnset();

    error NotFromMailbox(address from);
    error NotFromLumiaFactory(address sender);

    error UnsupportedMessage();

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
        string memory symbol,
        uint8 decimals
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
     * @notice Function called by the Mailbox contract when a message is received
     */
    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata data
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
     * @notice Updates the lumia factory contract recipient address for mailbox messages
     * @param lumiaFactory The new recipient address
     */
    function setLumiaFactory(address lumiaFactory) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Returns Lockbox data, including mailbox address, destination, and recipient address
    function lockboxData() external view returns (LockboxData memory);

    /// @notice Helper: separated function for getting mailbox dispatch quote
    function quoteDispatchTokenDeploy(
        address tokenAddress,
        string memory name,
        string memory symbol,
        uint8 decimals
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
        string memory symbol,
        uint8 decimals
    ) external pure returns (bytes memory body);

    /// @notice Helper: separated function for generating hyperlane message body
    function generateTokenBridgeBody(
        address vaultToken,
        address sender,
        uint256 shares
    ) external pure returns (bytes memory body);
}
