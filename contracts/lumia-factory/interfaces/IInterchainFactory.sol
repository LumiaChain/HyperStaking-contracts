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

    event RedeemTokenDispatched(
        address indexed mailbox,
        address recipient,
        address indexed vaultToken,
        address indexed user,
        uint256 shares
    );

    event MailboxUpdated(address indexed oldMailbox, address indexed newMailbox);
    event DestinationUpdated(uint32 indexed oldDestination, uint32 indexed newDestination);
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
    error UnrecognizedVaultToken();
    error UnsupportedMessage();

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
     * @notice Initiates token redemption
     * @dev Handles cross-chain unstaking via hyperlane bridge
     * @param vaultToken_ Address of the vault token (on the origin chain) to redeem
     * @param spender_ Address of the user whose process is initiated
     * @param shares_ Amount of shares to redeem
     */
    function redeemLpTokensDispatch(
        address vaultToken_,
        address spender_,
        uint256 shares_
    ) external payable;

    /**
     * @notice Updates the mailbox address used for interchain messaging
     * @param newMailbox_ The new mailbox address
     */
    function setMailbox(address newMailbox_) external;

    /**
     * @notice Updates the destination chain ID for the route
     * @param destination The new destination chain ID
     */
    function setDestination(uint32 destination) external;

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

    /**
     * @dev Utilizes the `.get` function from OpenZeppelin EnumerableMap to retrieve
     *      the lpToken associated with a given vaultToken.
     *
     * @param vaultToken_ The address of the vaultToken to look up.
     * @return lpToken The address of the lpToken corresponding to the provided vaultToken.
     */
    function getLpToken(address vaultToken_) external view returns (address lpToken);

    /**
     * @dev Utilizes the `.at` function from OpenZeppelin EnumerableMap
     *
     * @param index The position in the map to retrieve the key-value pair from
     * @return key The key (vaultToken) at the specified position
     * @return value The value (lpToken) at the specified position
     */
    function tokensMapAt(uint256 index) external view returns (address key, address value);

    /// @notice Helper: separated function for getting mailbox dispatch quote
    function quoteDispatchTokenRedeem(
        address vaultToken,
        address sender,
        uint256 shares
    ) external view returns (uint256);

    /// @notice Helper: separated function for generating hyperlane message body
    function generateTokenRedeemBody(
        address vaultToken,
        address sender,
        uint256 shares
    ) external pure returns (bytes memory body);
}
