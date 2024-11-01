// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategyVault} from "../interfaces/IStrategyVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IERC20, IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {
    LibStaking, StakingStorage, UserPoolInfo, StakingPoolInfo
} from "../libraries/LibStaking.sol";
import {
    LibStrategyVault, StrategyVaultStorage, UserVaultInfo, VaultInfo, VaultTier1, VaultTier2
} from "../libraries/LibStrategyVault.sol";

import {LiquidVaultToken} from "../LiquidVaultToken.sol";

/**
 * @title StrategyVaultFacet
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract StrategyVaultFacet is IStrategyVault, HyperStakingAcl, ReentrancyGuardUpgradeable {
    using CurrencyHandler for Currency;
    using SafeERC20 for IERC20Metadata;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    function deposit(
        address strategy,
        address user,
        uint256 amount
    ) external payable diamondInternal {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultTier1 storage tier1 = v.vaultTier1Info[strategy];

        StakingStorage storage s = LibStaking.diamondStorage();
        StakingPoolInfo storage pool = s.poolInfo[vault.poolId];

        {
            UserVaultInfo storage userVault = v.userInfo[strategy][user];
            UserPoolInfo storage userPool = s.userInfo[vault.poolId][user];

            userVault.allocationPoint = _calculateNewAllocPoint(
                userVault,
                strategy,
                amount
            );

            _lockUserStake(userPool, userVault, tier1, amount);
        }

        // allocate stake amount in strategy
        // and receive allocation
        uint256 allocation;
        if (pool.currency.isNativeCoin()) {
            allocation = IStrategy(strategy).allocate{value: amount}(amount, user);
        } else {
            pool.currency.approve(strategy, amount);
            allocation = IStrategy(strategy).allocate(amount, user);
        }

        // fetch allocation to this vault
        tier1.assetAllocation += allocation;
        vault.asset.safeTransferFrom(strategy, address(this), allocation);

        emit Deposit(vault.poolId, strategy, user, amount, allocation);
    }

    function withdraw(
        address strategy,
        address user,
        uint256 amount
    ) external diamondInternal returns (uint256 withdrawAmount) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultTier1 storage tier1 = v.vaultTier1Info[strategy];

        StakingStorage storage s = LibStaking.diamondStorage();

        uint256 allocation = _convertToTier1Allocation(tier1, amount);
        tier1.assetAllocation -= allocation;

        {
            UserVaultInfo storage userVault = v.userInfo[strategy][user];
            UserPoolInfo storage userPool = s.userInfo[vault.poolId][user];

            // withdraw does not change user allocation point

            _unlockUserStake(userPool, userVault, tier1, amount);
        }

        vault.asset.safeIncreaseAllowance(strategy, allocation);
        withdrawAmount = IStrategy(strategy).exit(allocation, user);

        emit Withdraw(vault.poolId, strategy, user, amount, allocation);
    }

    // ========= Managed ========= //

    function addStrategy(
        uint256 poolId,
        address strategy,
        IERC20Metadata asset,
        uint256 tier1RevenueFee
    ) external onlyStrategyVaultManager nonReentrant {
        _createVault(poolId, strategy, asset, tier1RevenueFee);
    }

    function setTier1RevenueFee(address strategy, uint256 revenueFee) external onlyStrategyVaultManager nonReentrant {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        v.vaultTier1Info[strategy].revenueFee = revenueFee;
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
    function vaultTier1Info(address strategy) external view returns (VaultTier1 memory) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        return v.vaultTier1Info[strategy];
    }

    /// @inheritdoc IStrategyVault
    function vaultTier2Info(address strategy) external view returns (VaultTier2 memory) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        return v.vaultTier2Info[strategy];
    }

    /// @inheritdoc IStrategyVault
    function userContribution(address strategy, address user) public view returns (uint256) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();

        UserVaultInfo memory userVault = v.userInfo[strategy][user];
        VaultTier1 memory tier1 = v.vaultTier1Info[strategy];

        if (userVault.stakeLocked == 0) {
            return 0;
        }

        return userVault.stakeLocked * LibStaking.PRECISION_FACTOR / tier1.totalStakeLocked;
    }

    /// TODO try to simplify calculations
    /// @inheritdoc IStrategyVault
    function userRevenue(address strategy, address user) external view returns (uint256 revenue) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();

        // current allocation price
        uint8 assetDecimals = v.vaultInfo[strategy].asset.decimals();
        uint256 allocationPrice = IStrategy(strategy).convertToAllocation(10 ** assetDecimals);

        UserVaultInfo storage userVault = v.userInfo[strategy][user];

        // allocation price hasn't increased, no revenue is generated
        if (userVault.allocationPoint >= allocationPrice) {
            return 0;
        }

        // asset price difference multiplied by locked stake
        uint256 assetRevenue =
            (allocationPrice - userVault.allocationPoint) * userVault.stakeLocked
            / LibStaking.PRECISION_FACTOR;

        // revenue represented in stake
        revenue = IStrategy(strategy).convertToStake(assetRevenue);
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    function _lockUserStake(
        UserPoolInfo storage userPool,
        UserVaultInfo storage userVault,
        VaultTier1 storage tier1,
        uint256 amount
    ) internal {
        userPool.stakeLocked += amount;
        userVault.stakeLocked += amount;
        tier1.totalStakeLocked += amount;
    }

    function _unlockUserStake(
        UserPoolInfo storage userPool,
        UserVaultInfo storage userVault,
        VaultTier1 storage tier1,
        uint256 amount
    ) internal {
        userPool.stakeLocked -= amount;
        userVault.stakeLocked -= amount;
        tier1.totalStakeLocked -= amount;
    }

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

    function _createVault(
        uint256 poolId,
        address strategy,
        IERC20Metadata asset,
        uint256 tier1RevenueFee
    ) internal {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();

        require(v.vaultInfo[strategy].poolId == 0, VaultAlreadyExist());

        // create a new VaultInfo and store it in storage
        v.vaultInfo[strategy] = VaultInfo({
            poolId: poolId,
            strategy: strategy,
            asset: asset
        });

        // init tier1
        v.vaultTier1Info[strategy] = VaultTier1({
            assetAllocation: 0,
            totalStakeLocked: 0,
            revenueFee: tier1RevenueFee
        });

        // init tier2

        // deploy vaultToken which represent shares to this strategy vault
        IERC4626 vaultToken = _deployVaultToken(asset);

        v.vaultTier2Info[strategy] = VaultTier2({
            vaultToken: vaultToken
        });

        emit VaultCreate(
            msg.sender,
            poolId,
            strategy,
            address(asset),
            address(vaultToken)
        );
    }

    // ========= View ========= //

    /**
     * @notice Calculates the new allocation point
     * @dev This function calculates a potential new allocation point for the given user and amount
     * @param userVault The user's current vault information
     * @param strategy The strategy contract address, used for converting `amount` to an allocation
     * @param amount The new amount being hypothetically added to the user's locked stake
     * @return The calculated allocation point based on the weighted average
     */
    function _calculateNewAllocPoint(
        UserVaultInfo storage userVault,
        address strategy,
        uint256 amount
    ) internal view returns (uint256) {
        uint256 newAllocation = IStrategy(strategy).convertToAllocation(amount);

        // Weighted average calculation for the updated allocation point
        return (
            userVault.stakeLocked * userVault.allocationPoint
            + newAllocation * LibStaking.PRECISION_FACTOR
        ) / (userVault.stakeLocked + amount);
    }

    function _convertToTier1Allocation(
        VaultTier1 storage tier1,
        uint256 amount
    ) internal view returns (uint256) {
        // amout ratio of the total stake locked in vault
        uint256 amountRatio = (amount * LibStaking.PRECISION_FACTOR / tier1.totalStakeLocked);
        return amountRatio * tier1.assetAllocation / LibStaking.PRECISION_FACTOR;
    }

    // ========= Pure ========= //

    /// @notice Helper function for string concatenation
    function _concat(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }
}
