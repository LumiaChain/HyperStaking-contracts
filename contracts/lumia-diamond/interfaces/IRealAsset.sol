// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

/**
 * @title IRealAsset
 * @dev Interface for RealAssetFacet
 */
interface IRealAsset {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event DirectRwaMint(
        address indexed strategy,
        address indexed rwaAsset,
        address sender,
        uint256 stakeAmount
    );

    event DirectRwaRedeem(
        address indexed strategy,
        address indexed rwaAsset,
        address from,
        address to,
        uint256 assetAmount
    );

    event RwaAssetSet(
        address indexed strategy,
        address newRwaAssetOwner,
        address newRwaAsset
    );

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /// @notice Handles the direct minting of RWA tokens based on the provided data
    function handleDirectMint(bytes calldata data) external;

    /// @notice Handles the direct redemption of bridged RWA tokens for a user
    function handleDirectRedeem(
        address strategy,
        address from,
        address to,
        uint256 assetAmount
    ) external payable;

    /// @notice Sets the RWA asset contract for a given strategy
    function setRwaAsset(address strategy, address rwaAsset) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Retrieves the RWA asset token contract associated with a strategy
    function getRwaAsset(address strategy) external view returns (address);

    /// @notice Returns the amount of assets a user has bridged for a given strategy
    function getUserBridgedState(address strategy, address user) external view returns (uint256);
}
