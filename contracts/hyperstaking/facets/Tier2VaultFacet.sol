// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ITier2Vault} from "../interfaces/ITier2Vault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {ILockbox} from "../interfaces/ILockbox.sol";

import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {
    LibHyperStaking, HyperStakingStorage, VaultInfo, VaultTier2, UserTier2Info
} from "../libraries/LibHyperStaking.sol";

/**
 * @title Tier2VaultFacet
 *
 * @dev This contract is a facet of Diamond Proxy
 */
contract Tier2VaultFacet is ITier2Vault, HyperStakingAcl, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using CurrencyHandler for Currency;

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error NotVaultToken();

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    modifier onlyVaultToken(address strategy) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultTier2 storage tier2 = v.vaultTier2Info[strategy];

        require(msg.sender == address(tier2.vaultToken), NotVaultToken());
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc ITier2Vault
    function joinTier2(
        address strategy,
        address user,
        uint256 stake
    ) external payable diamondInternal {
        VaultInfo storage vault = LibHyperStaking.diamondStorage().vaultInfo[strategy];

        // allocate stake amount in strategy
        // and receive allocation
        uint256 allocation;
        if (vault.stakeCurrency.isNativeCoin()) {
            allocation = IStrategy(strategy).allocate{value: stake}(stake, user);
        } else {
            vault.stakeCurrency.approve(strategy, stake);
            allocation = IStrategy(strategy).allocate(stake, user);
        }

        // fetch allocation to this vault
        vault.asset.safeTransferFrom(strategy, address(this), allocation);

        // mint and bridge vaultToken shares
        _bridgeVaultTokens(strategy, user, stake, allocation);

        emit Tier2Join(strategy, user, allocation);
    }

    /// @inheritdoc ITier2Vault
    function joinTier2WithAllocation(
        address strategy,
        address user,
        uint256 allocation
    ) external payable diamondInternal {
        // recalculate stake amount based on exit allocation instead of the initial stake
        // use the current price, allocation ration == include generated revenue
        uint256 stake = IStrategy(strategy).previewExit(allocation);

        // mint and bridge vaultToken shares
        _bridgeVaultTokens(strategy, user, stake, allocation);

        emit Tier2Join(strategy, user, allocation);
    }

    /// @inheritdoc ITier2Vault
    function leaveTier2(
        address strategy,
        address user,
        uint256 allocation
    ) external onlyVaultToken(strategy) nonReentrant returns (uint256 withdrawAmount) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultTier2 storage tier2 = v.vaultTier2Info[strategy];

        // VaultToken should approved DIAMOND first
        vault.asset.safeTransferFrom(address(tier2.vaultToken), address(this), allocation);

        vault.asset.safeIncreaseAllowance(strategy, allocation);
        withdrawAmount = IStrategy(strategy).exit(allocation, user);

        vault.stakeCurrency.transfer(user, withdrawAmount);

        emit Tier2Leave(strategy, user, withdrawAmount, allocation);
    }

    // ========= View ========= //

    /// @inheritdoc ITier2Vault
    function vaultTier2Info(address strategy) external view returns (VaultTier2 memory) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        return v.vaultTier2Info[strategy];
    }

    /// @inheritdoc ITier2Vault
    function userTier2Info(
        address strategy,
        address user
    ) external view returns (UserTier2Info memory) {
        VaultTier2 storage tier2 = LibHyperStaking.diamondStorage().vaultTier2Info[strategy];
        uint256 shares = tier2.vaultToken.balanceOf(user);

        return sharesTier2Info(strategy, shares);
    }

    /// @inheritdoc ITier2Vault
    function sharesTier2Info(
        address strategy,
        uint256 shares
    ) public view returns (UserTier2Info memory) {
        VaultTier2 storage tier2 = LibHyperStaking.diamondStorage().vaultTier2Info[strategy];

        uint256 allocation = tier2.vaultToken.convertToAssets(shares);
        uint256 stake = IStrategy(strategy).previewExit(allocation);

        return UserTier2Info({
            shares: shares,
            allocation: allocation,
            stake: stake
        });
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice helper function which mints, locks and initiates bridge token transfer
    function _bridgeVaultTokens(
        address strategy,
        address user,
        uint256 stake,
        uint256 allocation
    ) internal {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        VaultTier2 storage tier2 = v.vaultTier2Info[strategy];

        vault.asset.safeIncreaseAllowance(address(tier2.vaultToken), allocation);

        // vaultToken - shares are deposited to Lockbox (this diamond facet)
        uint256 shares = tier2.vaultToken.deposit(allocation, address(this));

        // quote message fee for forwarding a TokenBridge message across chains
        uint256 fee = ILockbox(address(this)).quoteDispatchTokenBridge(
            strategy,
            user,
            stake,
            shares
        );

        ILockbox(address(this)).tokenBridgeDispatch{value: fee}(
            strategy,
            user,
            stake,
            shares
        );
    }
}
