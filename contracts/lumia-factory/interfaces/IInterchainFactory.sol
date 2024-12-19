// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";

/**
 * @title IInterchainFactory
 * @dev Interface for InterchainFactory
 */
interface IInterchainFactory {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event ReceivedMessage(
        uint32 indexed origin,
        bytes32 indexed sender,
        uint256 value,
        string message
    );

    event TokenDeployed(address originToken, address lpToken, string name, string symbol);
    event TokenBridged(
        address indexed originToken,
        address indexed lpToken,
        address indexed sender,
        uint256 amount
    );

    event MailboxUpdated(address indexed oldMailbox, address indexed newMailbox);
    event OriginLockboxUpdated(address indexed oldLockbox, address indexed newLockbox);

    //===========================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error NotFromMailbox(address from);
    error NotFromLumiaLockbox(address sender);

    error OriginLockboxNotSet();
    error LumiaReceiverNotSet();

    error InvalidMailbox(address badMailbox);
    error InvalidLumiaReceiver(address badReceiver);

    error TokenAlreadyDeployed();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Function called by the Mailbox contract when a message is received
     */
    function handle(
        uint32 origin_,
        bytes32 sender_,
        bytes calldata data_
    ) external payable;

    /**
     * @notice Updates the mailbox address used for interchain messaging
     * @param newMailbox_ The new mailbox address
     */
    function setMailbox(address newMailbox_) external;

    /**
     * @notice Updates the origin lockbox address
     * @param newLockbox_ The new origin lockbox address
     */
    function setOriginLockbox(address newLockbox_) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    function mailbox() external view returns(IMailbox);

    function originLockbox() external view returns(address);

    function lastSender() external view returns(address);

    function lastData() external view returns(bytes memory);

    // HMH enuberable map getters?
}
