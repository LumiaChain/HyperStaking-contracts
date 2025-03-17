// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IMigration} from "../interfaces/IMigration.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IDeposit} from "../interfaces/IDeposit.sol";
import {ILockbox} from "../interfaces/ILockbox.sol";
import {ITier2Vault} from "../interfaces/ITier2Vault.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {Currency} from "../libraries/CurrencyHandler.sol";
import {
    LibHyperStaking, HyperStakingStorage, VaultInfo, Tier2Info, DirectStakeInfo
} from "../libraries/LibHyperStaking.sol";

/**
 * @title MigrationFacet
 * @notice Facet responsible for migration between strategies
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract MigrationFacet is IMigration, HyperStakingAcl {
    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IMigration
    function migrateStrategy(
        address fromStrategy,
        address toStrategy,
        uint256 amount
    ) external payable onlyMigrationManager {
        HyperStakingStorage storage hs = LibHyperStaking.diamondStorage();
        VaultInfo storage fromVault = hs.vaultInfo[fromStrategy];
        VaultInfo storage toVault = hs.vaultInfo[toStrategy];

        require(amount > 0, ZeroAmount());
        require(fromStrategy != toStrategy, SameStrategy());

        require(address(fromVault.strategy) != address(0), InvalidStrategy(fromStrategy));
        require(address(toVault.strategy) != address(0), InvalidStrategy(toStrategy));

        // both strategies should have the same stake currency
        Currency memory stakeCurrency = IStrategy(fromStrategy).stakeCurrency();
        require(
            stakeCurrency.token == IStrategy(toStrategy).stakeCurrency().token,
            InvalidCurrency()
        );

        // migration to direct staking makes no sense
        require(!IStrategy(toStrategy).isDirectStakeStrategy(), DirectStrategy());

        // ---

        if(IStrategy(fromStrategy).isDirectStakeStrategy()) {
            _migrateFromDirectStrategy(hs, fromStrategy, toStrategy, amount);
        } else {
            _migrateFromYieldStrategy(hs, fromStrategy, toStrategy, amount);
        }

        // ---

        emit StrategyMigrated(msg.sender, fromStrategy, toStrategy, amount);
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @dev separate function for specific directStake-type strategy migration
    function _migrateFromDirectStrategy(
        HyperStakingStorage storage hs,
        address fromStrategy,
        address toStrategy,
        uint256 amount
    ) internal {
        DirectStakeInfo storage fromDirectStake = hs.directStakeInfo[fromStrategy];
        uint256 availableAmount = fromDirectStake.totalStake;

        require(availableAmount >= amount, InsufficientAmount());

        fromDirectStake.totalStake -= amount;

        // false - bridge, no new rwa needs to be minted during migration
        ITier2Vault(address(this)).joinTier2(toStrategy, address(this), amount, false);

        _bridgeMigrationInfo(fromStrategy, toStrategy, amount);
    }

    /// @dev separate function for regular strategy migration
    function _migrateFromYieldStrategy(
        HyperStakingStorage storage hs,
        address fromStrategy,
        address toStrategy,
        uint256 amount
    ) internal {
        Tier2Info storage fromTier2 = hs.tier2Info[fromStrategy];

        // calculate available stake by previewing shares in vault
        uint256 totalShares = fromTier2.sharesMinted - fromTier2.sharesRedeemed;
        uint256 totalAllocation = fromTier2.vaultToken.previewRedeem(totalShares);
        uint256 availableAmount = IStrategy(fromStrategy).previewExit(totalAllocation);

        require(availableAmount >= amount, InsufficientAmount());

        // internal (to this address) Tier2 rejoin to another strategy
        uint256 withdrawn = IDeposit(address(this)).stakeWithdrawTier2(fromStrategy, amount, address(this));
        ITier2Vault(address(this)).joinTier2(toStrategy, address(this), withdrawn, false);

        _bridgeMigrationInfo(fromStrategy, toStrategy, amount);
    }

    /// @notice helper function which initiates bridge data transfer about migration
    function _bridgeMigrationInfo(
        address fromStrategy,
        address toStrategy,
        uint256 amount
    ) internal {
        // quote message fee for forwarding a TokenBridge message across chains
        uint256 fee = ILockbox(address(this)).quoteDispatchMigrationInfo(
            fromStrategy,
            toStrategy,
            amount
        );

        ILockbox(address(this)).migrationInfoDispatch{value: fee}(
            fromStrategy,
            toStrategy,
            amount
        );
    }
}
