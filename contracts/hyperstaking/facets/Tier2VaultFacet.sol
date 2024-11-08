// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ITier2Vault} from "../interfaces/ITier2Vault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {
    LibStaking, StakingStorage, StakingPoolInfo
} from "../libraries/LibStaking.sol";
import {
    LibStrategyVault, StrategyVaultStorage, VaultInfo, VaultTier2
} from "../libraries/LibStrategyVault.sol";

/**
 * @title Tier1VaultFacet
 *
 * @dev This contract is a facet of Diamond Proxy
 */
contract Tier2VaultFacet is ITier2Vault, HyperStakingAcl, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using CurrencyHandler for Currency;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// TODO
    /// @inheritdoc ITier2Vault
    function joinTier2(
        address strategy,
        address user,
        uint256 stake
    ) external payable diamondInternal {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        StakingStorage storage s = LibStaking.diamondStorage();
        StakingPoolInfo storage pool = s.poolInfo[vault.poolId];

        // allocate stake amount in strategy
        // and receive allocation
        uint256 allocation;
        if (pool.currency.isNativeCoin()) {
            allocation = IStrategy(strategy).allocate{value: stake}(stake, user);
        } else {
            pool.currency.approve(strategy, stake);
            allocation = IStrategy(strategy).allocate(stake, user);
        }

        // fetch allocation to this vault
        vault.asset.safeTransferFrom(strategy, address(this), allocation);

        emit Tier2Join(vault.poolId, strategy, user, stake, allocation);
    }

    /// TODO
    /// @inheritdoc ITier2Vault
    function leaveTier2(
        address strategy,
        address user,
        uint256 stake
    ) external diamondInternal returns (uint256 withdrawAmount) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        // StakingStorage storage s = LibStaking.diamondStorage();
        uint256 allocation; // = _convertToTier1Allocation(tier1, stake);

        vault.asset.safeIncreaseAllowance(strategy, allocation);
        withdrawAmount = IStrategy(strategy).exit(allocation, user);

        emit Tier2Leave(vault.poolId, strategy, user, stake, allocation);
    }

    // ========= View ========= //


    /// @inheritdoc ITier2Vault
    function vaultTier2Info(address strategy) external view returns (VaultTier2 memory) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        return v.vaultTier2Info[strategy];
    }
}
