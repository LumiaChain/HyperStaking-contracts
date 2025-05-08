// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {StakeInfoData} from "../libraries/HyperlaneMailboxMessages.sol";

/**
 * @title IStakeInfoRoute
 * @dev Interface for StakeInfoRoute
 */
interface IStakeInfoRoute {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event StakeInfoDispatched(
        address indexed mailbox,
        address lumiaFactory,
        address indexed strategy,
        address indexed user,
        uint256 stake
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
     * @notice Dispatches a cross-chain message informing about stake
     * @dev This function sends a message to trigger e.g. representing vault asset mint
     */
    function stakeInfoDispatch(StakeInfoData memory data) external payable;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Helper
    function quoteDispatchStakeInfo(StakeInfoData memory data) external view returns (uint256);

    /// @notice Helper
    function generateStakeInfoBody(
        StakeInfoData memory data
    ) external pure returns (bytes memory body);
}
