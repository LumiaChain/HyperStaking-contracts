// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {StakeRewardData} from "../libraries/HyperlaneMailboxMessages.sol";

/**
 * @title IStakeRewardRoute
 * @dev Interface for StakeRewardRoute
 */
interface IStakeRewardRoute {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event StakeRewardDispatched(
        address indexed mailbox,
        address lumiaFactory,
        address indexed strategy,
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
     * @notice Dispatches a cross-chain message informing about stake reward
     */
    function stakeRewardDispatch(StakeRewardData memory data) external payable;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Helper
    function quoteDispatchStakeReward(StakeRewardData memory data) external view returns (uint256);

    /// @notice Helper
    function generateStakeRewardBody(
        StakeRewardData memory data
    ) external pure returns (bytes memory body);
}
