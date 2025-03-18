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
    function handleRwaMint(
        address originLockbox,
        bytes calldata data
    ) external diamondInternal {
        address strategy = data.strategy();
        address sender = data.sender();
        uint256 stakeAmount = data.stakeAmount();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        LibInterchainFactory.checkRoute(ifs, strategy);

        RouteInfo storage r = ifs.routes[strategy];
        address rwaAsset = address(r.rwaAsset); // shortcut for visibility


        // store information about bridged state/stake
        ifs.userBridgedState[originLockbox][rwaAsset][sender] += stakeAmount;
        ifs.generalBridgedState[strategy] += stakeAmount;

        r.rwaAssetOwner.mint(sender, stakeAmount);

        emit RwaMint(strategy, rwaAsset, sender, stakeAmount);
    }

    /// @inheritdoc IRealAssets
    function handleRwaRedeem(
        address strategy,
        address from,
        address to,
        uint256 assetAmount
    ) external payable {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        LibInterchainFactory.checkRoute(ifs, strategy);

        RouteInfo storage r = ifs.routes[strategy];
        address rwaAsset = address(r.rwaAsset); // shortcut for visibility

        // require both user and general state
        require(
            ifs.userBridgedState[r.originLockbox][rwaAsset][from] >= assetAmount,
            InsufficientUserState()
        );
        require(ifs.generalBridgedState[strategy] >= assetAmount, InsufficientGeneralState());

        // decrease bridged state/stake
        ifs.userBridgedState[r.originLockbox][rwaAsset][from] -= assetAmount;
        ifs.generalBridgedState[strategy] -= assetAmount;

        IERC20(rwaAsset).safeTransferFrom(from, address(this), assetAmount);

        // use hyperlane handler function for dispatching rwaAsset
        IHyperlaneHandler(address(this)).stakeRedeemDispatch{value: msg.value}(
            strategy,
            to,
            assetAmount
        );

        emit RwaRedeem(strategy, rwaAsset, from, to, assetAmount);
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
    function getUserBridgedState(
        address originLockbox,
        address rwaAsset,
        address user
    ) external view returns (uint256) {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        return ifs.userBridgedState[originLockbox][rwaAsset][user];
    }

    /// @inheritdoc IRealAssets
    function getGeneralBridgedState(address strategy) external view returns (uint256) {
        return LibInterchainFactory.diamondStorage().generalBridgedState[strategy];
    }
}
