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

    event MigrationInfoDispatched(
        address indexed mailbox,
        address lumiaFactory,
        address indexed fromStrategy,
        address indexed toStrategy,
        uint256 migrationAmount
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

    // error RecipientUnset();

    error NotFromMailbox(address from);
    error NotFromLumiaFactory(address sender);

    error UnsupportedMessage();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Dispatches a cross-chain message informing about migration
     * @dev This function sends a message to setup migration route
     */
    function migrationInfoDispatch(
        address fromStrategy,
        address toStrategy,
        uint256 migrationAmount
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

    /// @notice Helper
    function quoteDispatchMigrationInfo(
        address fromStrategy,
        address toStrategy,
        uint256 migrationAmount
    ) external view returns (uint256);

    /// @notice Helper
    function generateMigrationInfoBody(
        address fromStrategy,
        address toStrategy,
        uint256 migrationAmount
    ) external pure returns (bytes memory body);
}
