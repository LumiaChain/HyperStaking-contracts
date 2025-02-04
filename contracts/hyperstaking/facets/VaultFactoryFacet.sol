// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IVaultFactory} from "../interfaces/IVaultFactory.sol";
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
    LibStrategyVault, StrategyVaultStorage, VaultInfo, VaultTier1, VaultTier2
} from "../libraries/LibStrategyVault.sol";

import {VaultToken} from "../VaultToken.sol";

/**
 * @title VaultFactoryFacet
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract VaultFactoryFacet is IVaultFactory, HyperStakingAcl, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Managed ========= //

    /// @inheritdoc IVaultFactory
    function addStrategy(
        uint256 poolId,
        Currency calldata currency,
        address strategy,
        string memory vaultTokenName,
        string memory vaultTokenSymbol,
        uint256 tier1RevenueFee
    ) external payable onlyStrategyVaultManager nonReentrant {
        // The ERC20-compliant asset associated with the strategy
        address asset = IStrategy(strategy).revenueAsset();

        IERC4626 vaultToken = _deployVaultToken(asset, strategy, vaultTokenName, vaultTokenSymbol);
        _storeVault(poolId, currency, strategy, asset, tier1RevenueFee, vaultToken);
    }

    // ========= View ========= //

    /// @inheritdoc IVaultFactory
    function vaultInfo(address strategy) external view returns (VaultInfo memory) {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        return v.vaultInfo[strategy];
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /**
     * @notice Dispatches an interchain message to instruct the deployment on the destination chain
     * @dev Uses the Lockbox Facet to send a message containing required details
     * @param vaultToken The address of the Vault token that the new LP token will represent
     */
    function _dispatchTokenDeploy(
        address vaultToken,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal {
        // quote message fee for forwarding a TokenDeploy message across chains
        uint256 fee = ILockbox(address(this)).quoteDispatchTokenDeploy(
            vaultToken,
            name,
            symbol,
            decimals
        );

        ILockbox(address(this)).tokenDeployDispatch{value: fee}(
            vaultToken,
            name,
            symbol,
            decimals
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

        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        _dispatchTokenDeploy(address(vaultToken), name, symbol, assetDecimals);
    }

    /**
     * @dev Initializes the vault storage for a given pool, sets the strategy and asset details,
     *      and applies the Tier 1 revenue fee
     *
     * @param currency The currency used as stake for this strategy
     * @param poolId The ID of the staking pool for which this vault is created
     * @param strategy The strategy address associated with this vault
     * @param asset The asset for the vault
     * @param tier1RevenueFee The revenue fee applied to Tier 1 users in this vault
     * @param vaultToken ERC4626 which represent shares to this strategy vault

     */
    function _storeVault(
        uint256 poolId,
        Currency calldata currency,
        address strategy,
        address asset,
        uint256 tier1RevenueFee,
        IERC4626 vaultToken
    ) internal {
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();
        require(v.vaultInfo[strategy].poolId == 0, VaultAlreadyExist());

        // create a new VaultInfo and store it in storage
        v.vaultInfo[strategy] = VaultInfo({
            poolId: poolId,
            stakeCurrency: currency,
            strategy: strategy,
            asset: IERC20Metadata(asset)
        });

        // init tier1
        v.vaultTier1Info[strategy] = VaultTier1({
            assetAllocation: 0,
            totalStake: 0,
            revenueFee: tier1RevenueFee
        });

        // init tier2
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
}
