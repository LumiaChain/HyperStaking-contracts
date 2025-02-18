// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IRouteFactory} from "../interfaces/IRouteFactory.sol";
import {LumiaDiamondAcl} from "../LumiaDiamondAcl.sol";
import {LumiaLPToken} from "../LumiaLPToken.sol";

import {
    LibInterchainFactory, InterchainFactoryStorage, RouteInfo
} from "../libraries/LibInterchainFactory.sol";

import {
    HyperlaneMailboxMessages
} from "../../hyperstaking/libraries/HyperlaneMailboxMessages.sol";

/**
 * @title RouteFactoryFacet
 * @notice Factory contract for deploying and managing LP tokens and 3adao integration
 */
contract RouteFactoryFacet is IRouteFactory, LumiaDiamondAcl {
    using HyperlaneMailboxMessages for bytes;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

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
        // TODO create Vault

        ifs.routes[strategy] = RouteInfo({
            exists: true,
            originLockbox: originLockbox,
            originDestination: originDestination,
            lpToken: lpToken
            // lendingVault TODO
        });

        emit TokenDeployed(strategy, address(lpToken), name, symbol, decimals);
    }

    /// @inheritdoc IRouteFactory
    /// @notice Handle specific TokenBridge message
    function handleTokenBridge(bytes calldata data) external diamondInternal {
        address strategy = data.strategy();
        address sender = data.sender();
        uint256 sharesAmount = data.sharesAmount();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        // revert if route not exists
        require(_routeExists(ifs, strategy), RouteDoesNotExist(strategy));

        RouteInfo storage r = ifs.routes[strategy];

        // mint LP tokens for the specified user
        r.lpToken.mint(sender, sharesAmount);

        emit TokenBridged(strategy, address(r.lpToken), sender, sharesAmount);
    }

    // ========= View ========= //

    /// @inheritdoc IRouteFactory
    function getLpToken(address strategy) external view returns (LumiaLPToken) {
        return LibInterchainFactory.diamondStorage().routes[strategy].lpToken;
    }

    /// @inheritdoc IRouteFactory
    function getRouteInfo(address strategy) external view returns (RouteInfo memory) {
        return LibInterchainFactory.diamondStorage().routes[strategy];
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Checks whether route exists
    function _routeExists(
        InterchainFactoryStorage storage ifs,
        address strategy
    ) internal view returns (bool){
        return ifs.routes[strategy].exists;
    }
}
