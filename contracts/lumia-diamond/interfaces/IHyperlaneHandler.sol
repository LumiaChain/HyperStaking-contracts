// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {RouteInfo, LastMessage} from "../libraries/LibInterchainFactory.sol";

/**
 * @title IHyperlaneHandler
 * @dev Interface for HyperlaneHandlerFacet
 */
interface IHyperlaneHandler {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event ReceivedMessage(
        uint32 indexed origin,
        bytes32 indexed sender,
        uint256 value,
        string message
    );

    event MailboxUpdated(address oldMailbox, address newMailbox);

    event AuthorizedOriginUpdated(
        address originLockbox,
        bool authorized,
        uint32 originDestination
    );

    event StakeRedeemDispatched(
        address indexed mailbox,
        address recipient,
        address indexed strategy,
        address indexed user,
        uint256 shares
    );

    event RouteRegistered(
        address indexed originLockbox,
        uint32 indexed originDestination,
        address strategy,
        address assetToken
        // address indexed sharesVault
    );

    //===========================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error InvalidMailbox(address badMailbox);
    error OriginUpdateFailed();

    error UnsupportedMessage();

    error NotFromHyperStaking(address sender);
    error BadOriginDestination(uint32 originDestination);

    error RouteAlreadyExist();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Function called by the Mailbox contract when a message is received
     */
    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata data
    ) external payable;

    /**
     * @notice Initiates stake redemption
     * @dev Handles cross-chain unstaking via hyperlane bridge
     */
    function stakeRedeemDispatch(
        address strategy,
        address to,
        uint256 assetAmount
    ) external payable;

    /**
     * @notice Updates the mailbox address used for interchain messaging
     * @param newMailbox The new mailbox address
     */
    function setMailbox(address newMailbox) external;

    /**
     * @notice Updates the authorization status of an origin Lockbox address
     * @param originLockbox The address of the origin Lockbox
     * @param authorized Whether the Lockbox should be authorized (true) or removed (false)
     * @param originDestination The destination chain Id associated with lockbox
     */
    function updateAuthorizedOrigin(
        address originLockbox,
        bool authorized,
        uint32 originDestination
    ) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Returns the mailbox saved in storage
    function mailbox() external view returns(IMailbox);

    /// @notice Returns the destination saved in storage
    function destination(address originLockbox) external view returns(uint32);

    /// @notice Returns the last message saved in storage
    function lastMessage() external view returns(LastMessage memory);

    /// @notice Helper: separated function for getting mailbox dispatch quote
    function quoteDispatchStakeRedeem(
        address strategy,
        address to,
        uint256 assetAmount
    ) external view returns (uint256);

    /// @notice Helper: separated function for generating hyperlane message body
    function generateStakeRedeemBody(
        address strategy,
        address to,
        uint256 assetAmount
    ) external pure returns (bytes memory body);

    /// @notice Returns detailed route information for a given strategy
    function getRouteInfo(address strategy) external view returns (RouteInfo memory);
}
