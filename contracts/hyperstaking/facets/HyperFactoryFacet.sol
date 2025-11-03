// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IHyperFactory} from "../interfaces/IHyperFactory.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IRouteRegistry} from "../interfaces/IRouteRegistry.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {RouteRegistryData} from "../libraries/HyperlaneMailboxMessages.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {
    LibHyperStaking, HyperStakingStorage, VaultInfo, StakeInfo
} from "../libraries/LibHyperStaking.sol";

/**
 * @title HyperFactoryFacet
 * @notice Facet responsible for initiating HyperStaking strategies on the origin chain, and initiates
 *         strategy registration on the Lumia chain, triggers cross-chain deployment of shares
 *         Acts as the entry point for adding and managing strategies within the protocol
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
        // The currency used for staking in this vault is taken from the strategy
        // Currency struct supports both native coin and erc20 tokens
        Currency memory stakeCurrency = IStrategy(strategy).stakeCurrency();

        address revenueAsset = address(0);

        // The ERC20-compliant asset associated with the strategy
        revenueAsset = IStrategy(strategy).revenueAsset();

        _storeVaultInfo(strategy, stakeCurrency, revenueAsset);

        // use stake currency decimals
        uint8 vaultDecimals = stakeCurrency.decimals();

        // register new route on lumia, deploy token representing it on lumia
        _dispatchRouteRegistry(strategy, vaultTokenName, vaultTokenSymbol, vaultDecimals);

        emit VaultCreate(
            msg.sender,
            strategy,
            stakeCurrency.token,
            revenueAsset,
            vaultTokenName,
            vaultTokenSymbol,
            vaultDecimals
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
     * @notice Initializes the vault and stake info for a given strategy
     */
    function _storeVaultInfo(
        address strategy,
        Currency memory stakeCurrency,
        address revenueAsset
    ) internal {
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();
        require(v.vaultInfo[strategy].strategy == address(0), VaultAlreadyExist());

        // save VaultInfo in storage
        v.vaultInfo[strategy] = VaultInfo({
            enabled: true,
            strategy: strategy,
            stakeCurrency: stakeCurrency,
            revenueAsset: IERC20Metadata(revenueAsset),
            feeRecipient: address(0),
            feeRate: 0,
            bridgeSafetyMargin: 0
        });

        // init stakeInfo
        v.stakeInfo[strategy] = StakeInfo({
            totalStake: 0,
            totalAllocation: 0,
            pendingExitStake: 0
        });
    }

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
}
