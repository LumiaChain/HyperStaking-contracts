// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStakeVault} from "../interfaces/IStakeVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IStakeInfoRoute} from "../interfaces/IStakeInfoRoute.sol";

import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {StakeInfoData} from "../libraries/HyperlaneMailboxMessages.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {
    LibHyperStaking, HyperStakingStorage, VaultInfo, StakeInfo
} from "../libraries/LibHyperStaking.sol";

/**
 * @title StakeVaultFacet
 *
 * @dev This contract is a facet of Diamond Proxy
 */
contract StakeVaultFacet is IStakeVault, HyperStakingAcl, ReentrancyGuardUpgradeable {
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
        StakeInfo storage si = v.stakeInfo[strategy];

        require(msg.sender == address(si.vaultToken), NotVaultToken());
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IStakeVault
    function join(
        address strategy,
        address user,
        uint256 stake
    ) external payable diamondInternal {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        StakeInfo storage si = v.stakeInfo[strategy];

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

        vault.asset.safeIncreaseAllowance(address(si.vaultToken), allocation);

        // vaultToken - shares are deposited to Lockbox (this diamond)
        uint256 shares = si.vaultToken.deposit(allocation, address(this));

        // save information
        si.sharesMinted += shares; // TODO: no shares here any more
        si.stakeBridged += stake; // TODO: remove?

        si.assetAllocation += allocation;

        // mint and shares and bridge stakeInfo
        _bridgeStakeInfo(strategy, user, stake, shares);

        emit Join(strategy, user, allocation);
    }

    /// @inheritdoc IStakeVault
    function leave(
        address strategy,
        address user,
        uint256 allocation
    ) external onlyVaultToken(strategy) nonReentrant returns (uint256 withdrawAmount) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        VaultInfo storage vault = v.vaultInfo[strategy];
        StakeInfo storage si = v.stakeInfo[strategy];

        // VaultToken should approved DIAMOND first
        vault.asset.safeTransferFrom(address(si.vaultToken), address(this), allocation);

        vault.asset.safeIncreaseAllowance(strategy, allocation);
        withdrawAmount = IStrategy(strategy).exit(allocation, user);

        vault.stakeCurrency.transfer(user, withdrawAmount);

        emit Leave(strategy, user, withdrawAmount, allocation);
    }

    /// @inheritdoc IStakeVault
    function collectRevenue(address strategy, address to, uint256 amount)
        external
        onlyVaultManager
    {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        StakeInfo storage si = v.stakeInfo[strategy];

        uint256 revenue = checkRevenue(strategy);
        require(amount <= revenue, InsufficientRevenue());

        uint256 allocation = IStrategy(strategy).previewAllocation(amount);
        si.vaultToken.withdraw(allocation, to, address(this));

        emit RevenueCollected(strategy, to, amount);
    }

    /// @inheritdoc IStakeVault
    function setBridgeSafetyMargin(address strategy, uint256 newMargin) external onlyVaultManager {
        require(newMargin >= LibHyperStaking.MIN_BRIDGE_SAFETY_MARGIN, SafetyMarginTooLow());

        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        StakeInfo storage si = v.stakeInfo[strategy];

        uint256 oldMargin = si.bridgeSafetyMargin;
        si.bridgeSafetyMargin = newMargin;

        emit BridgeSafetyMarginUpdated(oldMargin, newMargin);
    }

    // ========= View ========= //

    /// @inheritdoc IStakeVault
    function stakeInfo(address strategy) external view returns (StakeInfo memory) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        return v.stakeInfo[strategy];
    }

    /// @inheritdoc IStakeVault
    function checkRevenue(address strategy) public view returns (uint256) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        StakeInfo storage si = v.stakeInfo[strategy];

        // get the total diffeerence of shares
        uint256 shares = si.sharesMinted - si.sharesRedeemed;

        // calculate total possible stake withdraw
        uint256 allocation = si.vaultToken.previewRedeem(shares);
        uint256 stake = IStrategy(strategy).previewExit(allocation);

        // total stake that needs to be preserved for potential user bridge-outs
        uint256 bridgeCollateral = si.stakeBridged - si.stakeWithdrawn;

        // add safety margin to protect users from strategy asset volatility
        uint256 marginAmount = (
            bridgeCollateral * si.bridgeSafetyMargin
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

    /// @notice helper function which locks ERC4626 shares and initiates bridge data transfer
    function _bridgeStakeInfo(
        address strategy,
        address user,
        uint256 stake,
        uint256 shares
    ) internal {
        StakeInfoData memory data = StakeInfoData({
            strategy: strategy,
            sender: user,
            stakeAmount: stake,
            sharesAmount: shares
        });

        // quote message fee for forwarding a TokenBridge message across chains
        uint256 fee = IStakeInfoRoute(address(this)).quoteDispatchStakeInfo(data);

        // actual dispatch
        IStakeInfoRoute(address(this)).stakeInfoDispatch{value: fee}(data);
    }
}
