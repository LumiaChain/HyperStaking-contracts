// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {RouteInfo} from "../libraries/LibInterchainFactory.sol";
import {LumiaLPToken} from "../LumiaLPToken.sol";

/**
 * @title IRouteFactory
 * @dev Interface for RouteFactoryFacet
 */
interface IRouteFactory {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event TokenDeployed(
        address strategy,
        address lpToken,
        string name,
        string symbol,
        uint8 decimals
    );

    event TokenBridged(
        address indexed strategy,
        address indexed lpToken,
        address indexed sender,
        uint256 shares
    );

    event RedeemTokenDispatched(
        address indexed mailbox,
        address recipient,
        address indexed strategy,
        address indexed user,
        uint256 shares
    );

    //===========================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error RouteAlreadyExist();
    error RouteDoesNotExist(address strategy);

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /// @notice Handle specific TokenDeploy message
    function handleTokenDeploy(
        address originLockbox,
        uint32 originDestination,
        bytes calldata data
    ) external;

    /// @notice Handle specific TokenBridge message
    function handleTokenBridge(bytes calldata data) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Retrieves the lpToken associated with a given strategy
    function getLpToken(address strategy) external view returns (LumiaLPToken);

    /// @notice Returns more detailed route info for a given strategy
    function getRouteInfo(address strategy) external view returns (RouteInfo memory);
}
