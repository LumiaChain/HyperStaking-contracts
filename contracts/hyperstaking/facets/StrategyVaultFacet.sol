// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategyVault} from "../interfaces/IStrategyVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IRewarder} from "../interfaces/IRewarder.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {LibStaking, StakingStorage, UserPoolInfo, StakingPoolInfo} from "../libraries/LibStaking.sol";
import {
    LibStrategyVault, StrategyVaultStorage, UserVaultInfo, VaultInfo, VaultAsset
} from "../libraries/LibStrategyVault.sol";

import { LiquidVaultToken } from "../LiquidVaultToken.sol";

/**
 * @title StrategyVaultFacet
 *
 * @dev This contract is a facet of Diamond Proxy.
 * TODO ACL (or internal diamond)
 */
contract StrategyVaultFacet is IStrategyVault {
    using CurrencyHandler for Currency;
    using SafeERC20 for IERC20;

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    /**
     * @dev Rewarder calculations depends on the stake values and should be called before
     * updating them.
     */
    modifier updateRewards(address strategy, address user) {
        IRewarder(address(this)).updateActivePools(strategy, user);
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // TODO ACL
    function addStrategy(
        uint256 poolId,
        address strategy,
        IERC20Metadata asset
    ) external {
        _createVault( poolId, strategy, asset);
    }

    // TODO add non reentrant
    function deposit(
        address strategy,
        uint256 amount,
        address user
    ) external updateRewards(strategy, user) payable {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        UserVaultInfo storage userVault = v.userInfo[strategy][user];
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultAsset storage asset = v.vaultAssetInfo[strategy];

        StakingStorage storage s = LibStaking.diamondStorage();
        UserPoolInfo storage userPool = s.userInfo[vault.poolId][user];
        StakingPoolInfo storage pool = s.poolInfo[vault.poolId];

        userVault.stakeLocked += amount;
        vault.totalStakeLocked += amount;
        userPool.stakeLocked += amount;

        // allocate stake amount in strategy
        // and receive shares
        uint256 shares;
        if (pool.currency.isNativeCoin()) {
            shares = IStrategy(strategy).allocate{value: amount}(amount, user);
        } else {
            pool.currency.approve(strategy, amount);
            shares = IStrategy(strategy).allocate(amount, user);
        }

        // fetch shares to this vault
        asset.totalShares += shares;
        asset.asset.safeTransferFrom(strategy, address(this), shares);

        emit Deposit(vault.poolId, strategy, user, amount, shares);
    }

    // TODO add non reentrant
    function withdraw(
        address strategy,
        uint256 amount,
        address user
    ) external updateRewards(strategy, user) returns (uint256 withdrawAmount) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        UserVaultInfo storage userVault = v.userInfo[strategy][user];
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultAsset storage asset = v.vaultAssetInfo[strategy];

        StakingStorage storage s = LibStaking.diamondStorage();
        UserPoolInfo storage userPool = s.userInfo[vault.poolId][user];

        uint256 shares = convertToShares(strategy, amount);
        asset.totalShares -= shares;

        userVault.stakeLocked -= amount;
        vault.totalStakeLocked -= amount;
        userPool.stakeLocked -= amount;

        asset.asset.safeIncreaseAllowance(strategy, shares);
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

    function _deployVaultToken(IERC20Metadata asset) internal returns (IERC4626 vaultToken) {
        string memory sharesName = _concat("Lumia Liquid ", asset.name());
        string memory sharesSymbol = _concat("ll", asset.symbol());
        vaultToken = new LiquidVaultToken(
            address(this),
            IERC20(asset),
            sharesName,
            sharesSymbol
        );
    }

    function _createVault(uint256 poolId, address strategy, IERC20Metadata asset) internal {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();

        require(v.vaultInfo[strategy].poolId == 0, VaultAlreadyExist());

        // deploy vaultToken which represent shares to this strategy vault
        IERC4626 vaultToken = _deployVaultToken(asset);

        // create a new VaultInfo and store it in storage
        v.vaultInfo[strategy] = VaultInfo({
            poolId: poolId,
            strategy: strategy,
            totalStakeLocked: 0
        });

        // save VaultAsset for this strategy
        v.vaultAssetInfo[strategy] = VaultAsset({
            asset: asset,
            vaultToken: vaultToken,
            totalShares: 0
        });

        emit VaultCreate(
            msg.sender,
            poolId,
            strategy,
            address(asset),
            address(vaultToken)
        );
    }

    // ========= Pure ========= //

    /// @notice Helper function for string concatenation
    function _concat(string memory a, string memory b) internal pure returns (string memory){
        return string(abi.encodePacked(a, b));
    }
}
