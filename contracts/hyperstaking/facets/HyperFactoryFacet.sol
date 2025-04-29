// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IHyperFactory} from "../interfaces/IHyperFactory.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IRouteRegistry} from "../interfaces/IRouteRegistry.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IERC20, IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {RouteRegistryData} from "../libraries/HyperlaneMailboxMessages.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {
    LibHyperStaking, HyperStakingStorage, VaultInfo, DirectStakeInfo, StakeInfo
} from "../libraries/LibHyperStaking.sol";

import {VaultToken} from "../VaultToken.sol";

/**
 * @title HyperFactoryFacet
 * @notice Factory contract for creating and managing HyperStaking vaults
 * Deploys new vaults when adding strategies for asset management
 *
 * @dev This contract is a facet of Diamond Proxy
 */
contract HyperFactoryFacet is IHyperFactory, HyperStakingAcl, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using CurrencyHandler for Currency;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Managed ========= //

    /// @inheritdoc IHyperFactory
    function addStrategy(
        address strategy,
        string memory vaultTokenName,
        string memory vaultTokenSymbol
    ) external payable onlyVaultManager nonReentrant {
        // The ERC20-compliant asset associated with the strategy
        address asset = IStrategy(strategy).revenueAsset();
        uint8 assetDecimals = IERC20Metadata(asset).decimals();

        IERC4626 vaultToken = _deployVaultToken(asset, strategy, vaultTokenName, vaultTokenSymbol);
        _storeVaultInfo(strategy, asset, vaultToken);

        // register new route on lumia, deploy token representing it on lumia
        _dispatchRouteRegistry(strategy, vaultTokenName, vaultTokenSymbol, assetDecimals);

        emit VaultCreate(
            msg.sender,
            strategy,
            address(asset),
            vaultTokenName,
            vaultTokenSymbol
        );
    }

    /// TODO: when ERC4626 Vault will be moved to Lumia, try to combine addStrategy functions

    /// @inheritdoc IHyperFactory
    function addDirectStrategy(
        address strategy,
        string memory vaultTokenName,
        string memory vaultTokenSymbol
    ) external payable onlyVaultManager nonReentrant {
        require(IStrategy(strategy).isDirectStakeStrategy(), NotDirectStrategy(strategy));

        Currency memory asset = IStrategy(strategy).stakeCurrency();
        uint8 assetDecimals = asset.decimals();

        _storeVaultInfo(strategy, address(0), IERC4626(address(0)));

        // register new route on lumia, deploy token representing it on lumia
        _dispatchRouteRegistry(strategy, vaultTokenName, vaultTokenSymbol, assetDecimals);

        emit DirectVaultCreate(
            msg.sender,
            strategy,
            asset.token,
            vaultTokenName,
            vaultTokenSymbol
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
     * @dev Uses the RouteRegistry to send a message containing required details
     * @param strategy The address of the strategy which will be registered
     */
    function _dispatchRouteRegistry(
        address strategy,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal {
        RouteRegistryData memory data = RouteRegistryData({
            strategy: strategy,
            name: name,
            symbol: symbol,
            decimals: decimals,
            metadata: bytes("")
        });

        // quote message fee for forwarding a RouteRegistry message across chains
        uint256 fee = IRouteRegistry(address(this)).quoteDispatchRouteRegistry(data);

        // actual route dispatch
        IRouteRegistry(address(this)).routeRegistryDispatch{value: fee}(data);
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
     * @notice Initializes the vault and stake info for a given strategy and asset
     * @dev for direct: asset == address(0) should be used
     * @param strategy The strategy address associated with this vault
     * @param asset The stake asset for the vault
     * @param vaultToken ERC4626 which represent shares to this strategy vault
     */
    function _storeVaultInfo(
        address strategy,
        address asset,
        IERC4626 vaultToken
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

        // init stakeInfo
        if (IStrategy(strategy).isDirectStakeStrategy()) {
            // direct staking
            v.directStakeInfo[strategy] = DirectStakeInfo({
                totalStake: 0
            });
        } else {
            // active staking
            v.stakeInfo[strategy] = StakeInfo({
                vaultToken: vaultToken,
                totalStake: 0,
                assetAllocation: 0,
                bridgeSafetyMargin: 2e16, // 2%
                sharesMinted: 0,
                sharesRedeemed: 0,
                stakeBridged: 0,
                stakeWithdrawn: 0
            });
        }
    }
}
