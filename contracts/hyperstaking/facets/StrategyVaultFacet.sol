// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategyVault} from "../interfaces/IStrategyVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LibStaking, StakingStorage, UserPoolInfo} from "../libraries/LibStaking.sol";
import {
    LibStrategyVault, StrategyVaultStorage, UserVaultInfo, VaultInfo, VaultAsset
} from "../libraries/LibStrategyVault.sol";

/**
 * @title StrategyVaultFacet
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract StrategyVaultFacet is IStrategyVault {
    using SafeERC20 for IERC20;

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//


    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // TODO remove, only for testing purposes
    function init(
        uint256 poolId,
        address strategy,
        address token
    ) external {
        _createVault(poolId, strategy, VaultAsset({ token: token, totalShares: 0 }));
    }

    // TODO add non reentrant
    function deposit(
        address strategy,
        uint256 amount,
        address user
    ) external payable {
        StrategyVaultStorage storage r = LibStrategyVault.diamondStorage();
        StakingStorage storage s = LibStaking.diamondStorage();

        UserVaultInfo storage userVault = r.userInfo[strategy][user];
        VaultInfo storage vault = r.vaultInfo[strategy];
        VaultAsset storage asset = r.vaultAssetInfo[strategy];
        UserPoolInfo storage userPool = s.userInfo[vault.poolId][user];

        userVault.stakeLocked += amount;
        vault.totalStakeLocked += amount;
        userPool.stakeLocked += amount;

        // allocate stake amount in strategy
        uint256 shares = IStrategy(strategy).allocate{value: amount}(amount, user);

        // fetch shares to this vault
        IERC20(asset.token).safeTransferFrom(strategy, address(this), shares);
        asset.totalShares += shares;

        emit Deposit(vault.poolId, strategy, user, amount, shares);
    }

    // TODO add non reentrant
    function withdraw(
        address strategy,
        uint256 amount,
        address user
    ) external returns (uint256 withdrawAmount) {
        StrategyVaultStorage storage r = LibStrategyVault.diamondStorage();
        StakingStorage storage s = LibStaking.diamondStorage();

        UserVaultInfo storage userVault = r.userInfo[strategy][user];
        VaultInfo storage vault = r.vaultInfo[strategy];
        VaultAsset storage asset = r.vaultAssetInfo[strategy];
        UserPoolInfo storage userPool = s.userInfo[vault.poolId][user];

        uint256 shares = convertToShares(strategy, amount);

        userVault.stakeLocked -= amount;
        vault.totalStakeLocked -= amount;
        userPool.stakeLocked -= amount;

        asset.totalShares -= shares;

        IERC20(asset.token).safeIncreaseAllowance(strategy, shares);
        withdrawAmount = IStrategy(strategy).exit(shares, user);

        emit Withdraw(vault.poolId, strategy, user, amount, shares);
    }

    // ========= View ========= //

    /// @inheritdoc IStrategyVault
    function userVaultInfo(
        address strategy,
        address user
    ) external view returns (UserVaultInfo  memory) {
        StrategyVaultStorage storage r = LibStrategyVault.diamondStorage();
        return r.userInfo[strategy][user];
    }

    /// @inheritdoc IStrategyVault
    function vaultInfo(address strategy) external view returns (VaultInfo memory) {
        StrategyVaultStorage storage r = LibStrategyVault.diamondStorage();
        return r.vaultInfo[strategy];
    }

    /// @inheritdoc IStrategyVault
    function vaultAssetInfo(address strategy) external view returns (VaultAsset memory) {
        StrategyVaultStorage storage r = LibStrategyVault.diamondStorage();
        return r.vaultAssetInfo[strategy];
    }

    /// @inheritdoc IStrategyVault
    function convertToShares(
        address strategy,
        uint256 amount
    ) public view returns (uint256) {
        StrategyVaultStorage storage r = LibStrategyVault.diamondStorage();

        VaultInfo memory vault = r.vaultInfo[strategy];
        VaultAsset memory asset = r.vaultAssetInfo[strategy];

        // amout ratio of the total stake locked in vault
        uint256 amountRatio = (amount * LibStaking.PRECISSION_FACTOR / vault.totalStakeLocked);

        return amountRatio * asset.totalShares / LibStaking.PRECISSION_FACTOR;
    }

    /// @inheritdoc IStrategyVault
    function userContribution(address strategy, address user) public view returns (uint256) {
        StrategyVaultStorage storage r = LibStrategyVault.diamondStorage();

        UserVaultInfo memory userVault = r.userInfo[strategy][user];
        VaultInfo memory vault = r.vaultInfo[strategy];

        if (userVault.stakeLocked == 0 || vault.totalStakeLocked == 0) {
            return 0;
        }

        return userVault.stakeLocked * LibStaking.PRECISSION_FACTOR / vault.totalStakeLocked;
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//


    function _createVault(uint256 poolId, address strategy, VaultAsset memory asset) internal {
        StrategyVaultStorage storage r = LibStrategyVault.diamondStorage();

        require(r.vaultInfo[strategy].poolId == 0, VaultAlreadyExist());

        // create a new VaultInfo and store it in storage
        r.vaultInfo[strategy] = VaultInfo({
            poolId: poolId,
            strategy: strategy,
            totalStakeLocked: 0
        });

        // save VaultAsset for this strategy
        r.vaultAssetInfo[strategy] = asset;

        emit VaultCreate(msg.sender, poolId, strategy, asset.token);
    }
}
