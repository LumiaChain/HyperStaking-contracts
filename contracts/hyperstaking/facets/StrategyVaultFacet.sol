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

    // TODO ACL
    function addStrategy(
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
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        StakingStorage storage s = LibStaking.diamondStorage();

        UserVaultInfo storage userVault = v.userInfo[strategy][user];
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultAsset storage asset = v.vaultAssetInfo[strategy];
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
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        StakingStorage storage s = LibStaking.diamondStorage();

        UserVaultInfo storage userVault = v.userInfo[strategy][user];
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultAsset storage asset = v.vaultAssetInfo[strategy];
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
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        return v.userInfo[strategy][user];
    }

    /// @inheritdoc IStrategyVault
    function vaultInfo(address strategy) external view returns (VaultInfo memory) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        return v.vaultInfo[strategy];
    }

    /// @inheritdoc IStrategyVault
    function vaultAssetInfo(address strategy) external view returns (VaultAsset memory) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        return v.vaultAssetInfo[strategy];
    }

    /// @inheritdoc IStrategyVault
    function convertToShares(
        address strategy,
        uint256 amount
    ) public view returns (uint256) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();

        VaultInfo memory vault = v.vaultInfo[strategy];
        VaultAsset memory asset = v.vaultAssetInfo[strategy];

        // amout ratio of the total stake locked in vault
        uint256 amountRatio = (amount * LibStaking.PRECISION_FACTOR / vault.totalStakeLocked);

        return amountRatio * asset.totalShares / LibStaking.PRECISION_FACTOR;
    }

    /// @inheritdoc IStrategyVault
    function userContribution(address strategy, address user) public view returns (uint256) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();

        UserVaultInfo memory userVault = v.userInfo[strategy][user];
        VaultInfo memory vault = v.vaultInfo[strategy];

        if (userVault.stakeLocked == 0 || vault.totalStakeLocked == 0) {
            return 0;
        }

        return userVault.stakeLocked * LibStaking.PRECISION_FACTOR / vault.totalStakeLocked;
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//


    function _createVault(uint256 poolId, address strategy, VaultAsset memory asset) internal {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();

        require(v.vaultInfo[strategy].poolId == 0, VaultAlreadyExist());

        // create a new VaultInfo and store it in storage
        v.vaultInfo[strategy] = VaultInfo({
            poolId: poolId,
            strategy: strategy,
            totalStakeLocked: 0
        });

        // save VaultAsset for this strategy
        v.vaultAssetInfo[strategy] = asset;

        emit VaultCreate(msg.sender, poolId, strategy, asset.token);
    }
}
