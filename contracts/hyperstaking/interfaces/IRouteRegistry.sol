// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {RouteRegistryData} from "../../shared/libraries/HyperlaneMailboxMessages.sol";

/**
 * @title IRouteRegistry
 * @dev Interface for RouteRegistry
 */
interface IRouteRegistry {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event RouteRegistryDispatched(
        address indexed mailbox,
        address lumiaFactory,
        address indexed strategy,
        string name,
        string symbol,
        uint8 decimals
    );

    //===========================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error RecipientUnset();
    error DestinationUnset();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Dispatches a cross-chain message informing about new strategy to register
     * @dev This function sends a message to trigger new route registration
     */
    function routeRegistryDispatch(RouteRegistryData memory data) external payable;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Helper
    function quoteDispatchRouteRegistry(RouteRegistryData memory data) external view returns (uint256);

    /// @notice Helper: separated function for generating hyperlane message body
    function generateRouteRegistryBody(
        RouteRegistryData memory data
    ) external pure returns (bytes memory body);

}
