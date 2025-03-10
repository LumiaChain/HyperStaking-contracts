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
    LibHyperStaking, HyperStakingStorage, VaultInfo, Tier2Info, UserTier2Info
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
        Tier2Info storage tier2 = v.tier2Info[strategy];

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

        // mint and shares and bridge stakeInfo
        _bridgeStakeInfo(strategy, user, stake, allocation);

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

        // mint and shares and bridge stakeInfo
        _bridgeStakeInfo(strategy, user, stake, allocation);

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
        Tier2Info storage tier2 = v.tier2Info[strategy];

        // VaultToken should approved DIAMOND first
        vault.asset.safeTransferFrom(address(tier2.vaultToken), address(this), allocation);

        vault.asset.safeIncreaseAllowance(strategy, allocation);
        withdrawAmount = IStrategy(strategy).exit(allocation, user);

        vault.stakeCurrency.transfer(user, withdrawAmount);

        emit Tier2Leave(strategy, user, withdrawAmount, allocation);
    }

    /// @inheritdoc ITier2Vault
    function collectTier2Revenue(address strategy, address to, uint256 amount)
        external
        onlyVaultManager
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];

        uint256 revenue = checkTier2Revenue(strategy);
        require(amount <= revenue, InsufficientRevenue());

        vault.stakeCurrency.transfer(to, amount);

        emit Tier2RevenueCollected(strategy, to, amount);
    }

    /// @inheritdoc ITier2Vault
    function setBridgeSafetyMargin(address strategy, uint256 newMargin) external onlyVaultManager {
        require(newMargin >= LibHyperStaking.MIN_BRIDGE_SAFETY_MARGIN, SafetyMarginTooLow());

        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        Tier2Info storage tier2 = v.tier2Info[strategy];

        uint256 oldMargin = tier2.bridgeSafetyMargin;
        tier2.bridgeSafetyMargin = newMargin;

        emit BridgeSafetyMarginUpdated(oldMargin, newMargin);
    }

    // ========= View ========= //

    /// @inheritdoc ITier2Vault
    function tier2Info(address strategy) external view returns (Tier2Info memory) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        return v.tier2Info[strategy];
    }

    /// @inheritdoc ITier2Vault
    function userTier2Info(
        address strategy,
        address user
    ) external view returns (UserTier2Info memory) {
        Tier2Info storage tier2 = LibHyperStaking.diamondStorage().tier2Info[strategy];
        uint256 shares = tier2.vaultToken.balanceOf(user);

        return sharesTier2Info(strategy, shares);
    }

    /// @inheritdoc ITier2Vault
    function sharesTier2Info(
        address strategy,
        uint256 shares
    ) public view returns (UserTier2Info memory) {
        Tier2Info storage tier2 = LibHyperStaking.diamondStorage().tier2Info[strategy];

        uint256 allocation = tier2.vaultToken.convertToAssets(shares);
        uint256 stake = IStrategy(strategy).previewExit(allocation);

        return UserTier2Info({
            shares: shares,
            allocation: allocation,
            stake: stake
        });
    }

    /// @inheritdoc ITier2Vault
    function checkTier2Revenue(address strategy) public view returns (uint256) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        Tier2Info storage tier2 = v.tier2Info[strategy];

        // get the total diffeerence of shares
        uint256 shares = tier2.sharesMinted - tier2.sharesRedeemed;

        // calculate total possible stake withdraw
        uint256 allocation = tier2.vaultToken.previewRedeem(shares);
        uint256 stake = IStrategy(strategy).previewExit(allocation);

        // total stake that needs to be preserved for potential user bridge-outs
        uint256 bridgeCollateral = tier2.stakeBridged - tier2.stakeWithdrawn;

        // add safety margin to protect users from strategy asset volatility
        uint256 marginAmount = (
            bridgeCollateral * tier2.bridgeSafetyMargin
        ) / LibHyperStaking.PERCENT_PRECISION;

        // check for negative revenue
        if (bridgeCollateral + marginAmount > stake) {
            return 0;
        }

        return stake - (bridgeCollateral + marginAmount);
    }


    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice helper function which mints, locks ERC4626 shares and initiates bridge data transfer
    function _bridgeStakeInfo(
        address strategy,
        address user,
        uint256 stake,
        uint256 allocation
    ) internal {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        Tier2Info storage tier2 = v.tier2Info[strategy];

        vault.asset.safeIncreaseAllowance(address(tier2.vaultToken), allocation);

        // vaultToken - shares are deposited to Lockbox (this diamond)
        uint256 shares = tier2.vaultToken.deposit(allocation, address(this));

        // save information
        tier2.sharesMinted += shares;
        tier2.stakeBridged += stake;

        // quote message fee for forwarding a TokenBridge message across chains
        uint256 fee = ILockbox(address(this)).quoteDispatchStakeInfo(
            strategy,
            user,
            stake
        );

        ILockbox(address(this)).stakeInfoDispatch{value: fee}(
            strategy,
            user,
            stake
        );
    }
}
