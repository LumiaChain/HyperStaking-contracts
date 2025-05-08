// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

/**
 * @title IRealAssets
 * @dev Interface for RealAssetsFacet
 */
interface IRealAssets {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event RwaMint(
        address indexed strategy,
        address sender,
        uint256 stake,
        uint256 shares
    );

    event RwaRedeem(
        address indexed strategy,
        address from,
        address to,
        uint256 assets, // de facto stake
        uint256 shares
    );

    event StakeReward(
        address indexed strategy,
        uint256 stakeAdded
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error NotVaultToken();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /// @notice Handles the minting of RWA tokens based on the provided data
    function handleRwaMint(bytes calldata data) external;

    /// @notice Handles the stake reward distribution
    function handleStakeReward(bytes calldata data) external;

    /// @notice Handles the redemption of vault shares tokens for a user
    function handleRwaRedeem(
        address strategy,
        address from,
        address to,
        uint256 shares
    ) external payable;
}
