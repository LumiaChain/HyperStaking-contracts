// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IRealAsset} from "../interfaces/IRealAsset.sol";
import {LumiaDiamondAcl} from "../LumiaDiamondAcl.sol";
import {
    LibInterchainFactory, InterchainFactoryStorage, RouteInfo
} from "../libraries/LibInterchainFactory.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MintableToken} from "../../external/3adao-lumia/tokens/MintableToken.sol";
import {MintableTokenOwner} from "../../external/3adao-lumia/gobernance/MintableTokenOwner.sol";
import {
    HyperlaneMailboxMessages
} from "../../hyperstaking/libraries/HyperlaneMailboxMessages.sol";

/**
 * @title RealAssetFacet
 * @notice Facet responsible for minting and redeeming RWA (Real-World Asset) tokens
 */
contract RealAssetFacet is IRealAsset, LumiaDiamondAcl {
    using SafeERC20 for IERC20;
    using HyperlaneMailboxMessages for bytes;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Diamond Internal ========= //

    /// @inheritdoc IRealAsset
    function handleDirectMint(bytes calldata data) external diamondInternal {
        address strategy = data.strategy();
        address sender = data.sender();
        uint256 stakeAmount = data.stakeAmount();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        RouteInfo storage r = ifs.routes[strategy];

        LibInterchainFactory.checkRoute(ifs, strategy);

        ifs.userBridgedState[strategy][sender];

        r.rwaAssetOwner.mint(sender, stakeAmount);

        emit DirectRwaMint(strategy, address(r.rwaAsset), sender, stakeAmount);
    }

    /// @inheritdoc IRealAsset
    function handleDirectRedeem(
        address strategy,
        address user,
        uint256 assetAmount
    ) external payable {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        RouteInfo storage r = ifs.routes[strategy];

        LibInterchainFactory.checkRoute(ifs, strategy);

        // TODO
        emit DirectRwaRedeem(strategy, address(r.rwaAsset), user, assetAmount);
    }

    // ========= Restricted ========= //

    /// @inheritdoc IRealAsset
    function setRwaAsset(address strategy, address rwaAsset) external onlyLumiaFactoryManager {
        require(
            rwaAsset != address(0) && rwaAsset.code.length > 0,
            InvalidRwaAsset(rwaAsset)
        );

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        RouteInfo storage r = ifs.routes[strategy];

        LibInterchainFactory.checkRoute(ifs, strategy);

        r.rwaAsset = MintableToken(rwaAsset);
        r.rwaAssetOwner = MintableTokenOwner(r.rwaAsset.owner());

        emit RwaAssetSet(strategy, address(r.rwaAssetOwner), rwaAsset);
    }

    // ========= View ========= //

    /// @inheritdoc IRealAsset
    function getRwaAsset(address strategy) external view returns (address) {
        return address(LibInterchainFactory.diamondStorage().routes[strategy].rwaAsset);
    }

    /// @inheritdoc IRealAsset
    function getUserBridgedState(address strategy, address user) external view returns (uint256) {
        return LibInterchainFactory.diamondStorage().userBridgedState[strategy][user];
    }
}
