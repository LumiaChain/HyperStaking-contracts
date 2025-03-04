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
        address strategy,
        string name,
        string symbol,
        uint8 decimals
    );

    event TokenBridgeDispatched(
        address indexed mailbox,
        address lumiaFactory,
        address indexed strategy,
        address indexed user,
        uint256 stake,
        uint256 shares
    );

    event RouteRegistryDispatched(
        address indexed mailbox,
        address lumiaFactory,
        address indexed strategy,
        address rwaAsset
    );

    event StakeInfoDispatched(
        address indexed mailbox,
        address lumiaFactory,
        address indexed strategy,
        address indexed user,
        uint256 stake
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
        address strategy,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external payable;

    /**
     * @notice Dispatches a cross-chain message responsible for bridiging vault token
     * @dev This function sends a message to trigger the token mint process
     */
    function tokenBridgeDispatch(
        address strategy,
        address user,
        uint256 stake,
        uint256 shares
    ) external payable;

    /**
     * @notice Dispatches a cross-chain message informing about new strategy to register
     * @dev This function sends a message to trigger new route registration
     */
    function routeRegistryDispatch(
        address strategy,
        address rwaAsset
    ) external payable;

    /**
     * @notice Dispatches a cross-chain message informing about stake
     * @dev This function sends a message to trigger lumia rwa asset mint
     */
    function stakeInfoDispatch(
        address strategy,
        address user,
        uint256 stake
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
        address strategy,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external view returns (uint256);

    /// @notice Helper
    function quoteDispatchTokenBridge(
        address strategy,
        address sender,
        uint256 stake,
        uint256 shares
    ) external view returns (uint256);

    /// @notice Helper
    function quoteDispatchRouteRegistry(
        address strategy,
        address rwaAsset
    ) external view returns (uint256);

    /// @notice Helper
    function quoteDispatchStakeInfo(
        address strategy,
        address sender,
        uint256 stake
    ) external view returns (uint256);

    /// @notice Helper: separated function for generating hyperlane message body
    function generateTokenDeployBody(
        address strategy,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external pure returns (bytes memory body);

    /// @notice Helper
    function generateTokenBridgeBody(
        address strategy,
        address sender,
        uint256 stake,
        uint256 shares
    ) external pure returns (bytes memory body);

    /// @notice Helper
    function generateRouteRegistryBody(
        address strategy,
        address rwaAsset
    ) external pure returns (bytes memory body);

    /// @notice Helper
    function generateStakeInfoBody(
        address strategy,
        address sender,
        uint256 stake
    ) external pure returns (bytes memory body);
}
