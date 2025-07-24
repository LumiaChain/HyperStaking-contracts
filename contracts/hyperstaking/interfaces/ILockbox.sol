// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LockboxData, FailedRedeem} from "../libraries/LibHyperStaking.sol";

/**
 * @title ILockbox
 * @dev Interface for LockboxFacet
 */
interface ILockbox {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event ReceivedMessage(
        uint32 indexed origin,
        bytes32 indexed sender,
        uint256 value,
        string message
    );

    event DestinationUpdated(uint32 indexed oldDestination, uint32 indexed newDestination);

    event MailboxUpdated(address indexed oldMailbox, address indexed newMailbox);
    event MailboxChangeProposed(address newMailbox, uint256 applyAfter);

    event LumiaFactoryUpdated(address indexed oldLumiaFactory, address indexed newLumiaFactory);
    event LumiaFactoryChangeProposed(address newLumiaFactory, uint256 applyAfter);

    event StakeRedeemFailed(address indexed strategy, address indexed user, uint256 amount, uint256 id);
    event StakeRedeemReexecuted(
        address indexed strategy,
        address indexed user,
        uint256 amount,
        uint256 id
    );

    //===========================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error InvalidVaultToken(address badVaultToken);
    error InvalidMailbox(address badMailbox);
    error InvalidLumiaFactory(address badLumiaFactory);

    error PendingChangeFailed(address, uint256 applyAfter);

    error NotFromMailbox(address from);
    error NotFromLumiaFactory(address sender);

    error UnsupportedMessage();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /// @notice Helper function which locks assets and initiates bridge data transfer
    /// @dev Through StakeInfo route
    function bridgeStakeInfo(
        address strategy,
        address user,
        uint256 stake
    ) external payable;

    /// @notice Helper function which inform about stake added after report-compounding
    /// @dev Through StakeRreward route
    function bridgeStakeReward(
        address strategy,
        uint256 stakeAdded
    ) external payable;


    /// @notice Function called by the Mailbox contract when a message is received
    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata data
    ) external payable;

    /// @notice Re-executes a previously failed stake redeem operation
    /// @param id The ID of the failed redeem to reattempt
    function reexecuteStakeRedeem(uint256 id) external;

    /**
     * @notice Updates the destination chain ID for the route
     * @param destination The new destination chain ID
     */
    function setDestination(uint32 destination) external;

    /**
     * @notice Proposes a new mailbox address with delayed application
     * @param mailbox The new mailbox contract address
     */
    function proposeMailbox(address mailbox) external;

    /**
     * @notice Applies the proposed mailbox address after the delay
     */
    function applyMailbox() external;

    /**
     * @notice Proposes a new lumia factory address with delayed application
     * @param lumiaFactory The new factory address
     */
    function proposeLumiaFactory(address lumiaFactory) external;

    /**
     * @notice Applies the proposed lumia factory address after the delay
     */
    function applyLumiaFactory() external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Returns Lockbox data, including mailbox address, destination, and recipient address
    function lockboxData() external view returns (LockboxData memory);

    /// @notice Returns the total number of failed redeem attempts (counter)
    function getFailedRedeemCount() external view returns (uint256);

    /// @notice Returns failed redeem records by their IDs
    /// @param ids The list of failed redeem IDs to fetch
    function getFailedRedeems(uint256[] calldata ids)
        external
        view
        returns (FailedRedeem[] memory);

    /// @notice Returns list of failed redeem IDs associated with a given user
    function getUserFailedRedeemIds(address user) external view returns (uint256[] memory);
}
