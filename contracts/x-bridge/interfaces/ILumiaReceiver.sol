// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

/**
 * @title ILumiaReceiver
 * @notice Interface for lumia reveiver contract
 */
interface ILumiaReceiver {

    // ========= Errors ========= //

    error NotRegisteredToken(address token);
    error UnauthorizedBroker(address sender);

    // ========= Events ========= //

    event TokenRegistered(address indexed token, bool status);
    event TokensReceived(address indexed token, uint256 amount);
    event TokensEmitted(address indexed token, uint256 amount);
    event BrokerUpdated(address indexed oldBroker, address indexed newBroker);

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Records tokens received from bridging
     * @param amount_ The amount of tokens received
     */
    function tokensReceived(uint256 amount_) external;

    /**
     * @notice Emits tokens to the broker for further processing
     * @param token_ The token address to emit
     * @param amount_ The amount of tokens to emit
     */
    function emitTokens(address token_, uint256 amount_) external;

    /**
     * @notice Updates the registration status of a token
     * @param token_ The token address to register or unregister
     * @param status_ The registration status (true to register, false to unregister)
     */
    function updateRegisteredToken(address token_, bool status_) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Token address -> amount of tokens waiting to be bridged
    function waitings(address xerc20) external returns (uint256);
}
