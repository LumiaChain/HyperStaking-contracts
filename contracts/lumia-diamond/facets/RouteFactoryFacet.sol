// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IRouteFactory} from "../interfaces/IRouteFactory.sol";
import {IHyperlaneHandler} from "../interfaces/IHyperlaneHandler.sol";
import {LumiaDiamondAcl} from "../LumiaDiamondAcl.sol";
import {LumiaLPToken} from "../LumiaLPToken.sol";

import {MintableToken} from "../../external/3adao-lumia/tokens/MintableToken.sol";
import {MintableTokenOwner} from "../../external/3adao-lumia/gobernance/MintableTokenOwner.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    LibInterchainFactory, InterchainFactoryStorage, RouteInfo
} from "../libraries/LibInterchainFactory.sol";

import {
    HyperlaneMailboxMessages
} from "../../hyperstaking/libraries/HyperlaneMailboxMessages.sol";

import {SmartVault} from "../../external/3adao-lumia/vaults/SmartVault.sol";
import {IVaultFactory} from "../../external/3adao-lumia/interfaces/IVaultFactory.sol";
import {IVault} from "../../external/3adao-lumia/interfaces/IVault.sol";

/**
 * @title RouteFactoryFacet
 * @notice Factory contract for deploying and managing LP tokens and 3adao integration
 */
contract RouteFactoryFacet is IRouteFactory, LumiaDiamondAcl {
    using SafeERC20 for LumiaLPToken;
    using SafeERC20 for IERC20;
    using HyperlaneMailboxMessages for bytes;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Diamond Internal ========= //

    /// @inheritdoc IRouteFactory
    function handleTokenDeploy(
        address originLockbox,
        uint32 originDestination,
        bytes calldata data
    ) external diamondInternal {
        address strategy = data.strategy(); // origin strategy address
        string memory name = data.name();
        string memory symbol = data.symbol();
        uint8 decimals = data.decimals();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        require(_routeExists(ifs, strategy) == false, RouteAlreadyExist());

        LumiaLPToken lpToken = new LumiaLPToken(address(this), name, symbol, decimals);

        ifs.routes[strategy] = RouteInfo({
            exists: true,
            isLendingEnabled: true,
            originDestination: originDestination,
            originLockbox: originLockbox,
            lpToken: lpToken,
            lendingVault: _createLendingVault(ifs, name),
            borrowSafetyBuffer: 5e16, // 5%
            rwaAssetOwner: MintableTokenOwner(address(0)),
            rwaAsset: MintableToken(address(0))
        });

        emit TokenDeployed(strategy, address(lpToken), name, symbol, decimals);
    }

    /// @inheritdoc IRouteFactory
    function handleTokenBridge(bytes calldata data) external diamondInternal {
        address strategy = data.strategy();
        address sender = data.sender();
        uint256 stakeAmount = data.stakeAmount();
        uint256 sharesAmount = data.sharesAmount();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        // revert if route not exists
        require(_routeExists(ifs, strategy), RouteDoesNotExist(strategy));

        RouteInfo storage r = ifs.routes[strategy];

        if (r.isLendingEnabled) {
            // calc borrow value with safety margin
            uint256 rwaAmount = stakeAmount
                * (LibInterchainFactory.PERCENT_PRECISION - r.borrowSafetyBuffer) // e.g. 100% - 5%
                / LibInterchainFactory.PERCENT_PRECISION;

            // mint LP tokens in order to add collateral to the lending vault
            r.lpToken.mint(address(this), sharesAmount);
            r.lpToken.safeIncreaseAllowance(address(ifs.vaultFactory), sharesAmount);
            ifs.vaultFactory.addCollateral(
                address(r.lendingVault),
                address(r.lpToken),
                sharesAmount
            );

            ifs.vaultFactory.borrow(address(r.lendingVault), rwaAmount, sender);
            emit CollateralBridged(
                strategy,
                address(r.lpToken),
                address(r.lendingVault),
                sender,
                sharesAmount,
                rwaAmount
            );
        } else {
            // mint LP tokens for the specified user
            r.lpToken.mint(sender, sharesAmount);
            emit TokenBridged(strategy, address(r.lpToken), sender, sharesAmount);
        }
    }

    /// @inheritdoc IRouteFactory
    function redeemRwaTokens(
        address strategy,
        address user,
        uint256 shares
    ) external payable {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        // revert if route not exists
        require(_routeExists(ifs, strategy), RouteDoesNotExist(strategy));

        RouteInfo storage r = ifs.routes[strategy];

        // redeemed collateral is lpToken shares
        (uint256 rwaAmount, uint256 redeemptionFee) =  r.lendingVault.calcRedeem(
            address(r.lpToken),
            shares
        );

        // transfer from stable needed to repay vault
        IERC20(ifs.vaultFactory.stable()).safeTransferFrom(
            msg.sender,
            address(this),
            rwaAmount + redeemptionFee
        );

        IERC20(ifs.vaultFactory.stable()).safeIncreaseAllowance(
            address(ifs.vaultFactory),
            rwaAmount + redeemptionFee
        );

        // actual redeem
        ifs.vaultFactory.redeem(
            address(r.lendingVault),
            address(r.lpToken),
            shares,
            address(this)
        );

        IERC20(r.lpToken).safeIncreaseAllowance(address(this), shares);

        // use hyperlane handler function for dispatching lpToken
        IHyperlaneHandler(address(this)).redeemLpTokensDispatch{value: msg.value}(
            strategy,
            user,
            shares
        );

        emit RwaTokenRedeemed(
            strategy,
            address(r.lendingVault),
            address(r.lpToken),
            user,
            shares,
            rwaAmount,
            redeemptionFee
        );
    }

    // ========= Restricted ========= //

    /// @inheritdoc IRouteFactory
    function setVaultFactory(address newVaultFactory) external onlyLumiaFactoryManager {
        require(
            newVaultFactory != address(0) && newVaultFactory.code.length > 0,
            InvalidVaultFactory(newVaultFactory)
        );

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        emit VaultFactoryUpdated(address(ifs.vaultFactory), newVaultFactory);
        ifs.vaultFactory = IVaultFactory(newVaultFactory);
    }

    /// @inheritdoc IRouteFactory
    function updateLendingProperties(
        address strategy,
        bool enabled,
        uint256 borrowSafetyBuffer
    ) external onlyLumiaFactoryManager {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        require(_routeExists(ifs, strategy), RouteDoesNotExist(strategy));

        RouteInfo storage r = ifs.routes[strategy];

        r.isLendingEnabled = enabled;
        if (enabled) {
            require(borrowSafetyBuffer <= 50e16, InvalidSafetyBuffer());
            r.borrowSafetyBuffer = borrowSafetyBuffer;
        }

        emit LendingPropertiesUpdated(strategy, enabled, borrowSafetyBuffer);
    }

    /// @inheritdoc IRouteFactory
    function collectVaultYield(
        address strategy,
        uint256 amount,
        address to
    ) external onlyLumiaFactoryManager {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        require(_routeExists(ifs, strategy), RouteDoesNotExist(strategy));

        RouteInfo storage r = ifs.routes[strategy];

        ifs.vaultFactory.borrow(address(r.lendingVault), amount, to);
        emit VaultYieldCollected(strategy, address(r.lendingVault), amount, to);
    }

    /// @inheritdoc IRouteFactory
    function transferVaultOwnership(
        address strategy,
        address to
    ) external onlyLumiaFactoryManager {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        require(_routeExists(ifs, strategy), RouteDoesNotExist(strategy));

        RouteInfo storage r = ifs.routes[strategy];
        Ownable(address(r.lendingVault)).transferOwnership(to);
        emit VaultOwnershipTransfered(strategy, address(r.lendingVault), to);
    }

    // ========= View ========= //

    /// @inheritdoc IRouteFactory
    function getVaultFactory() external view returns (IVaultFactory) {
        return LibInterchainFactory.diamondStorage().vaultFactory;
    }

    /// @inheritdoc IRouteFactory
    function getLpToken(address strategy) external view returns (LumiaLPToken) {
        return LibInterchainFactory.diamondStorage().routes[strategy].lpToken;
    }

    /// @inheritdoc IRouteFactory
    function getLendingVault(address strategy) external view returns (IVault) {
        return LibInterchainFactory.diamondStorage().routes[strategy].lendingVault;
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Creates new 3adao Vault using vaultFactory from the storage
    function _createLendingVault(
        InterchainFactoryStorage storage ifs,
        string memory lpTokenName
    ) internal returns (IVault) {
        address lendingVault = ifs.vaultFactory.createVault(
            string(abi.encodePacked("HyperStaking Vault: ", lpTokenName))
        );

        /// assign the operator role so that operations can continue after
        SmartVault(lendingVault).addOperator(address(this));

        return IVault(lendingVault);
    }

    /// @notice Checks whether route exists
    function _routeExists(
        InterchainFactoryStorage storage ifs,
        address strategy
    ) internal view returns (bool){
        return ifs.routes[strategy].exists;
    }
}
