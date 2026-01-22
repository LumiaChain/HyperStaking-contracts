// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IStrategy} from "../hyperstaking/interfaces/IStrategy.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CurveIntegrationFacet} from "../hyperstaking/facets/integrations/CurveIntegrationFacet.sol";
import {SuperformIntegrationFacet} from "../hyperstaking/facets/integrations/SuperformIntegrationFacet.sol";
import {EmaPricingFacet} from "../hyperstaking/facets/EmaPricingFacet.sol";

import {SuperformConfig, LibSuperform} from "../hyperstaking/libraries/LibSuperform.sol";
import {LibCurve} from "../hyperstaking/libraries/LibCurve.sol";
import {LibAcl} from "../hyperstaking/libraries/LibAcl.sol";

import {Currency, CurrencyHandler} from "../shared/libraries/CurrencyHandler.sol";

/**
 * @title TestSwapIntegration
 * @dev On-chain test implementation of merged ISuperformIntegration and ICurveIntegration
 *      deploys without the diamond proxy and invokes Superform/Curve contracts directly
 */
contract TestSwapIntegration is SuperformIntegrationFacet, CurveIntegrationFacet, EmaPricingFacet {
    using SafeERC20 for IERC20;
    using CurrencyHandler for Currency;

    error UnsupportedAsyncCall();

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    /// @notice Test Constructor for both Superform and Curve integrations
    /// @dev initialize because of the upgradeable acl
    function initialize(
        address superformFactory_,
        address superformRouter_,
        address superPositions_,
        address curveRouter_,
        address strategyManager
    ) public initializer {
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _grantRole(LibAcl.STRATEGY_MANAGER_ROLE, strategyManager);

        SuperformConfig memory superformConfig = SuperformConfig({
            superformFactory: superformFactory_,
            superformRouter: superformRouter_,
            superPositions: superPositions_
        });

        // init Superform and Curve storage
        LibSuperform.init(superformConfig);
        LibCurve.setRouter(curveRouter_);
    }

    /* ========== Test Functions ========== */

    function allocate(address strategy, uint256 amount) external returns (uint256 allocation) {
        Currency memory stakeCurrency = IStrategy(strategy).stakeCurrency();

        // fetch stake to this contract
        stakeCurrency.transferFrom(msg.sender, address(this), amount);

        // request allocation
        uint256 requestId = 1;
        uint64 readyAt = IStrategy(strategy).requestAllocation(requestId, amount, address(this));

        require(readyAt == 0, UnsupportedAsyncCall());
        uint256[] memory ids = new uint256[](1); ids[0] = requestId;

        // claim & send asset to the user
        allocation = IStrategy(strategy).claimAllocation(ids, msg.sender);
    }

    function exit(address strategy, uint256 amount) external returns (uint256 exitStake) {
        address revenueAsset = IStrategy(strategy).revenueAsset();

        // fetch asset to this contract
        IERC20(revenueAsset).transferFrom(msg.sender, address(this), amount);

        // request exit
        uint256 requestId = 2;
        uint64 readyAt = IStrategy(strategy).requestExit(requestId, amount, address(this));

        require(readyAt == 0, UnsupportedAsyncCall());
        uint256[] memory ids = new uint256[](1); ids[0] = requestId;

        // claim exit & send stake to the user
        exitStake = IStrategy(strategy).claimExit(ids, msg.sender);
    }
}
