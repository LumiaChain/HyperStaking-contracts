// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {StakeRedeemData} from "../../shared/libraries/HyperlaneMailboxMessages.sol";

/**
 * @title IStakeRedeemRoute
 * @dev Interface for StakeRedeemRoute
 */
interface IStakeRedeemRoute {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event StakeRedeemDispatched(
        address indexed mailbox,
        address recipient,
        uint64 nonce,
        address indexed strategy,
        address indexed user,
        uint256 shares
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
     * @notice Initiates stake redemption
     * @dev Handles cross-chain unstaking via hyperlane bridge
     */
    function stakeRedeemDispatch(
        StakeRedeemData memory data
    ) external payable;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Helper: separated function for getting mailbox dispatch quote
    function quoteDispatchStakeRedeem(
        StakeRedeemData memory data
    ) external view returns (uint256);

    /// @notice Helper: separated function for generating hyperlane message body
    function generateStakeRedeemBody(
        StakeRedeemData memory data
    ) external pure returns (bytes memory body);
}
