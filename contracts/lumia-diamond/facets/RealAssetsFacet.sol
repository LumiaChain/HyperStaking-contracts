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

        // store information about bridged state/stake
        ifs.generalBridgedState[strategy] += stakeAmount;
        // TODO add minted shares?

        // TODO handle vault shares
        // r.rwaAssetOwner.mint(sender, stakeAmount);

        emit RwaMint(strategy, sender, stakeAmount);
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

        // TODO check rather balance of shares
        // require both user and general state
        // require(
        //     ifs.userBridgedState[r.originLockbox][rwaAsset][from] >= assetAmount,
        //     InsufficientUserState()
        // );
        require(ifs.generalBridgedState[strategy] >= assetAmount, InsufficientGeneralState());

        // decrease bridged state/stake
        ifs.generalBridgedState[strategy] -= assetAmount;

        // TODO transfer rather vault shares
        // IERC20(rwaAsset).safeTransferFrom(from, address(this), assetAmount);

        // use hyperlane handler function for dispatching rwaAsset
        IHyperlaneHandler(address(this)).stakeRedeemDispatch{value: msg.value}(
            strategy,
            to,
            assetAmount
        );

        emit RwaRedeem(strategy, from, to, assetAmount);
    }

    // ========= View ========= //

    /// @inheritdoc IRealAssets
    function getGeneralBridgedState(address strategy) external view returns (uint256) {
        return LibInterchainFactory.diamondStorage().generalBridgedState[strategy];
    }
}
