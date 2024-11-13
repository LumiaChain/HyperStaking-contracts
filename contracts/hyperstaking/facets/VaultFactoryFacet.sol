// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IVaultFactory} from "../interfaces/IVaultFactory.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IERC20, IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

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
        address strategy,
        IERC20Metadata asset,
        uint256 tier1RevenueFee
    ) external onlyStrategyVaultManager nonReentrant {
        _createVault(poolId, strategy, asset, tier1RevenueFee);
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
     * @notice Deploys a new vault token for a given asset
     * @dev Creates a new `LiquidVaultToken` instance with names and symbols derived from the asset
     * @param asset The underlying asset for the vault token, which provides name and symbol info
     * @return vaultToken The newly created vault token that conforms to the IERC4626 standard
     */
    function _deployVaultToken(
        IERC20Metadata asset,
        address strategy
    ) internal returns (IERC4626 vaultToken) {

        string memory sharesName = _concat("Lumia Liquid ", asset.name());
        string memory sharesSymbol = _concat("ll", asset.symbol());
        vaultToken = new VaultToken(
            address(this),
            strategy,
            IERC20(asset),
            sharesName,
            sharesSymbol
        );
    }

    /**
     * @notice Creates a new vault for a specific asset and strategy
     * @dev Initializes the vault storage for a given pool, sets the strategy and asset details,
     *      and applies the Tier 1 revenue fee
     * @param poolId The ID of the staking pool for which this vault is created
     * @param strategy The strategy address associated with this vault
     * @param asset The asset for the vault, whose metadata will define the vault's token
     * @param tier1RevenueFee The revenue fee applied to Tier 1 users in this vault
     */
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
        IERC4626 vaultToken = _deployVaultToken(asset, strategy);

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

    // ========= Pure ========= //

    /// @notice Helper function for string concatenation
    function _concat(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }
}
