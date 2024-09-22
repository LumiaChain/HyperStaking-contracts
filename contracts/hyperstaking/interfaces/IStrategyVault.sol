// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {UserVaultInfo, VaultInfo, VaultAsset} from "../libraries/LibStrategyVault.sol";

/**
 * @title IStrategyVault
 */
interface IStrategyVault {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event Deposit(
        uint256 indexed poolId,
        address indexed strategy,
        address indexed user,
        uint256 stake,
        uint256 shares
    );

    event Withdraw(
        uint256 indexed poolId,
        address indexed strategy,
        address indexed user,
        uint256 amount,
        uint256 shares
    );

    event VaultCreate(
        address indexed from,
        uint256 indexed poolId,
        address strategy,
        address token
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

        /// @notice Thrown when attempting to create a vault using the same strategy
        error VaultAlreadyExist();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /// @notice Initializes the contract with one vault // TODO test function - remove
    function init(uint256 poolId, address strategy, address token) external;

    function deposit(address strategy, uint256 amount, address user) external payable;

    function withdraw(address strategy, uint256 shares, address user) external returns (uint256);

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    function userVaultInfo(
        address strategy,
        address user
    ) external view returns (UserVaultInfo memory);

    function vaultInfo(address strategy) external view returns (VaultInfo memory);

    function vaultAssetInfo(address strategy) external view returns (VaultAsset memory);

    function convertToShares(address strategy, uint256 amount) external view returns (uint256);

    function userContribution(address strategy, address user) external view returns (uint256);
}
