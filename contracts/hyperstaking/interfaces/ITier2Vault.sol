// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {Tier2Info, UserTier2Info} from "../libraries/LibHyperStaking.sol";

/**
 * @title ITierVault
 * @dev Interface for Tier1VaultFacet
 */
interface ITier2Vault {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event Tier2Join(
        address indexed strategy,
        address indexed user,
        uint256 allocation
    );

    event Tier2Leave(
        address indexed strategy,
        address indexed user,
        uint256 stake,
        uint256 allocation
    );

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Join Tier 2 for a specified strategy by staking a certain amount
     * @param strategy The strategy for which the user is joining Tier 2
     * @param user The address of the user
     * @param stake The stake amount
     */
    function joinTier2(address strategy, address user, uint256 stake) external payable;

    /**
     * @notice Join Tier 2 for a specified strategy with asset instead of stake
     * @dev Used in migration process
     * @param strategy The strategy for which the user is joining Tier 2
     * @param user The address of the user
     * @param allocation The asset allocation amount
     */
    function joinTier2WithAllocation(
        address strategy,
        address user,
        uint256 allocation
    ) external payable;

    /**
     * @notice Leave Tier 2 for a specified strategy and asset amount.
     * @param strategy The strategy from which the user is leaving Tier 2
     * @param user The address of the user
     * @param allocation The amount of asset allocation from ValutToken
     * @return The total withdrawal amount, including the stake, generated revenue, after fees
     */
    function leaveTier2(
        address strategy,
        address user,
        uint256 allocation
    ) external returns (uint256);

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /**
     * @notice Retrieves Tier 2 information for a specified strategy
     * @param strategy The address of the strategy
     * @return The Tier1Info struct containing information about this specific tier
     */
    function tier2Info(address strategy) external view returns (Tier2Info memory);

    /**
     * @notice Retrieves tier2 information specific to a user within a given strategy
     * @dev Checks shares only on the chain from which it is called
     * @param strategy The address of the strategy
     * @param user The address of the user
     * @return A UserTier2Info struct containing the user's specific vault details
     */
    function userTier2Info(
        address strategy,
        address user
    ) external view returns (UserTier2Info memory);

     /**
     * @notice Retrieves tier2 information for a given amount of vault shares
     * @dev Useful, for example, when shares are bridged to another chain
     * @param strategy The address of the strategy
     * @param shares Amount of shares
     * @return A UserTier2Info struct containing the specific 'user' vault details
     */
    function sharesTier2Info(
        address strategy,
        uint256 shares
    ) external view returns (UserTier2Info memory);
}
