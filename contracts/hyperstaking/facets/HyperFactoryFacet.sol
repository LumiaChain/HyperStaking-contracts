// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IHyperFactory} from "../interfaces/IHyperFactory.sol";
import {ILockbox} from "../interfaces/ILockbox.sol";
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

import {Currency} from "../libraries/CurrencyHandler.sol";
import {
    LibHyperStaking, HyperStakingStorage, VaultInfo, Tier1Info, Tier2Info
} from "../libraries/LibHyperStaking.sol";

import {VaultToken} from "../VaultToken.sol";

/**
 * @title HyperFactoryFacet
 * @notice Factory contract for creating and managing HyperStaking vaults
 * Deploys new vaults when adding strategies for asset management
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract HyperFactoryFacet is IHyperFactory, HyperStakingAcl, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Managed ========= //

    /// @inheritdoc IHyperFactory
    function addStrategy(
        address strategy,
        string memory vaultTokenName,
        string memory vaultTokenSymbol,
        uint256 tier1RevenueFee,
        address lumiaRwaAsset
    ) external payable onlyVaultManager nonReentrant {
        // The ERC20-compliant asset associated with the strategy
        address asset = IStrategy(strategy).revenueAsset();

        IERC4626 vaultToken = _deployVaultToken(asset, strategy, vaultTokenName, vaultTokenSymbol);
        _storeVaultTiers(strategy, tier1RevenueFee, vaultToken);
        _storeVaultInfo(strategy, asset);

        // register new route on lumia
        _dispatchRouteRegistry(strategy, lumiaRwaAsset);

        emit VaultCreate(
            msg.sender,
            strategy,
            address(asset),
            address(vaultToken),
            lumiaRwaAsset
        );
    }

    /// @inheritdoc IHyperFactory
    function addDirectStrategy(
        address strategy,
        address lumiaRwaAsset
    ) external payable onlyVaultManager nonReentrant {
        require(IStrategy(strategy).isDirectStakeStrategy(), NotDirectStrategy(strategy));

        _storeVaultInfo(strategy, address(0));

        // register new route on lumia
        _dispatchRouteRegistry(strategy, lumiaRwaAsset);

        emit DirectVaultCreate(
            msg.sender,
            strategy,
            lumiaRwaAsset
        );
    }

    /// @inheritdoc IHyperFactory
    function setStrategyEnabled(address strategy, bool enabled) external onlyVaultManager {
        VaultInfo storage vault = LibHyperStaking.diamondStorage().vaultInfo[strategy];

        require(address(vault.strategy) != address(0), VaultDoesNotExist(strategy));

        // set value only if differs
        if (vault.enabled != enabled) {
            vault.enabled = enabled;
            emit VaultEnabledSet(strategy, enabled);
        }
    }

    // ========= View ========= //

    /// @inheritdoc IHyperFactory
    function vaultInfo(address strategy) external view returns (VaultInfo memory) {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        return v.vaultInfo[strategy];
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /**
     * @notice Dispatches an interchain message to instruct the registration of new strategy
     * @dev Uses the Lockbox Facet to send a message containing required details
     * @param strategy The address of the strategy which will be registered
     * @param lumiaRwaAsset The RWA token address representing the bridged asset on the lumia chain
     */
    function _dispatchRouteRegistry(
        address strategy,
        address lumiaRwaAsset
    ) internal {
        // quote message fee for forwarding a RouteRegistry message across chains
        uint256 fee = ILockbox(address(this)).quoteDispatchRouteRegistry(
            strategy,
            lumiaRwaAsset
        );

        ILockbox(address(this)).routeRegistryDispatch{value: fee}(
            strategy,
            lumiaRwaAsset
        );
    }

    /**
     * @notice Deploys a new vault ERC4626 token for a given asset and strategy
     * @param asset The underlying asset for the vault token
     * @return vaultToken The newly created vault token that conforms to the IERC4626 standard
     */
    function _deployVaultToken(
        address asset,
        address strategy,
        string memory name,
        string memory symbol
    ) internal returns (IERC4626 vaultToken) {
        vaultToken = new VaultToken(
            address(this),
            strategy,
            IERC20(asset),
            name,
            symbol
        );
    }

    /**
     * @dev Store information about tiers for a given strategy, vault token and tier 1 revenue fee
     *
     * @param strategy The strategy address associated with this vault
     * @param tier1RevenueFee The revenue fee applied to Tier 1 users in this vault
     * @param vaultToken ERC4626 which represent shares to this strategy vault
     */
    function _storeVaultTiers(
        address strategy,
        uint256 tier1RevenueFee,
        IERC4626 vaultToken
    ) internal {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        require(v.vaultInfo[strategy].strategy == address(0), VaultAlreadyExist());

        // init tier1
        v.tier1Info[strategy] = Tier1Info({
            assetAllocation: 0,
            totalStake: 0,
            revenueFee: tier1RevenueFee
        });

        // init tier2
        v.tier2Info[strategy] = Tier2Info({
            vaultToken: vaultToken,
            bridgeSafetyMargin: 2e16, // 2%
            sharesMinted: 0,
            sharesRedeemed: 0,
            stakeBridged: 0,
            stakeWithdrawn: 0
        });
    }

    /**
     * @notice Initializes the vault info for a given strategy and asset
     * @dev for direct: asset == address(0) should be used
     * @param strategy The strategy address associated with this vault
     * @param asset The asset for the vault
     */
    function _storeVaultInfo(
        address strategy,
        address asset
    ) internal {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        require(v.vaultInfo[strategy].strategy == address(0), VaultAlreadyExist());

        // The currency used for staking in this vault is taken from the strategy
        // Currency struct supports both native coin and erc20 tokens
        Currency memory stakeCurrency = IStrategy(strategy).stakeCurrency();

        // save VaultInfo in storage
        v.vaultInfo[strategy] = VaultInfo({
            enabled: true,
            stakeCurrency: stakeCurrency,
            strategy: strategy,
            asset: IERC20Metadata(asset)
        });
    }
}
