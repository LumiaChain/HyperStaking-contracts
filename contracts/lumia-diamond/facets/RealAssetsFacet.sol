// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IRealAssets} from "../interfaces/IRealAssets.sol";
import {IHyperlaneHandler} from "../interfaces/IHyperlaneHandler.sol";
import {LumiaDiamondAcl} from "../LumiaDiamondAcl.sol";
import {
    LibInterchainFactory, InterchainFactoryStorage, RouteInfo
} from "../libraries/LibInterchainFactory.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMintableToken} from "../../external/3adao-lumia/interfaces/IMintableToken.sol";
import {IMintableTokenOwner} from "../../external/3adao-lumia/interfaces/IMintableTokenOwner.sol";
import {
    HyperlaneMailboxMessages
} from "../../hyperstaking/libraries/HyperlaneMailboxMessages.sol";

/**
 * @title RealAssetsFacet
 * @notice Facet responsible for minting and redeeming RWA (Real-World Asset) tokens
 */
contract RealAssetsFacet is IRealAssets, LumiaDiamondAcl {
    using SafeERC20 for IERC20;
    using HyperlaneMailboxMessages for bytes;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Diamond Internal ========= //

    /// @inheritdoc IRealAssets
    function handleRwaMint(bytes calldata data) external diamondInternal {
        address strategy = data.strategy();
        address sender = data.sender();
        uint256 stakeAmount = data.stakeAmount();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        RouteInfo storage r = ifs.routes[strategy];

        LibInterchainFactory.checkRoute(ifs, strategy);

        // store information about bridged stake
        ifs.userBridgedState[strategy][sender] += stakeAmount;

        r.rwaAssetOwner.mint(sender, stakeAmount);

        emit RwaMint(strategy, address(r.rwaAsset), sender, stakeAmount);
    }

    /// @inheritdoc IRealAssets
    function handleRwaRedeem(
        address strategy,
        address from,
        address to,
        uint256 assetAmount
    ) external payable {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        address rwaAsset = address(ifs.routes[strategy].rwaAsset);

        LibInterchainFactory.checkRoute(ifs, strategy);

        // decrease bridged stake
        require(ifs.userBridgedState[strategy][from] >= assetAmount, InsufficientBridgedState());
        ifs.userBridgedState[strategy][from] -= assetAmount;

        IERC20(rwaAsset).safeTransferFrom(from, address(this), assetAmount);

        // use hyperlane handler function for dispatching rwaAsset
        IHyperlaneHandler(address(this)).stakeRedeemDispatch{value: msg.value}(
            strategy,
            to,
            assetAmount
        );

        emit RwaRedeem(strategy, rwaAsset, from, to, assetAmount);
    }

    /// @inheritdoc IRealAssets
    function handleMigratedRwaRedeem(
        address fromStrategy,
        address toStrategy,
        address from,
        address to,
        uint256 assetAmount
    ) external payable {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        // rwaAsset is the same in both strategies
        address rwaAsset = address(ifs.routes[fromStrategy].rwaAsset);

        LibInterchainFactory.checkRoute(ifs, fromStrategy);
        LibInterchainFactory.checkRoute(ifs, toStrategy);

        // still require user to have a sufficient balance in the 'from' strategy
        require(ifs.userBridgedState[fromStrategy][from] >= assetAmount, InsufficientBridgedState());

        // and that the migration state should also be sufficient
        require(ifs.migrationsState[fromStrategy][toStrategy] >= assetAmount, InsufficientMigrationState());

        // decrease both values
        ifs.userBridgedState[fromStrategy][from] -= assetAmount;
        ifs.migrationsState[fromStrategy][toStrategy] -= assetAmount;

        IERC20(rwaAsset).safeTransferFrom(from, address(this), assetAmount);

        // dispatching rwaAsset using "toStrategy"
        IHyperlaneHandler(address(this)).stakeRedeemDispatch{value: msg.value}(
            toStrategy,
            to,
            assetAmount
        );

        emit MigratedRwaRedeem(fromStrategy, toStrategy, rwaAsset, from, to, assetAmount);
    }

    // ========= Restricted ========= //

    /// @inheritdoc IRealAssets
    function setRwaAsset(address strategy, address rwaAsset) external onlyLumiaFactoryManager {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        RouteInfo storage r = ifs.routes[strategy];

        LibInterchainFactory.checkRoute(ifs, strategy);
        LibInterchainFactory.checkRwaAsset(rwaAsset);

        r.rwaAsset = IMintableToken(rwaAsset);
        r.rwaAssetOwner = IMintableTokenOwner(r.rwaAsset.owner());

        emit RwaAssetSet(strategy, address(r.rwaAssetOwner), rwaAsset);
    }

    // ========= View ========= //

    /// @inheritdoc IRealAssets
    function getRwaAsset(address strategy) external view returns (address) {
        return address(LibInterchainFactory.diamondStorage().routes[strategy].rwaAsset);
    }

    /// @inheritdoc IRealAssets
    function getUserBridgedState(address strategy, address user) external view returns (uint256) {
        return LibInterchainFactory.diamondStorage().userBridgedState[strategy][user];
    }
}
