// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../hyperstaking/interfaces/IStrategy.sol";

import {CurveIntegrationFacet} from "../hyperstaking/facets/integrations/CurveIntegrationFacet.sol";
import {SuperformIntegrationFacet} from "../hyperstaking/facets/integrations/SuperformIntegrationFacet.sol";

import {LibSuperform} from "../hyperstaking/libraries/LibSuperform.sol";
import {LibCurve} from "../hyperstaking/libraries/LibCurve.sol";
import {LibAcl} from "../hyperstaking/libraries/LibAcl.sol";
import {Currency, CurrencyHandler} from "../hyperstaking/libraries/CurrencyHandler.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TestSwapIntegration
 * @dev On-chain test implementation of merged ISuperformIntegration and ICurveIntegration
 *      deploys without the diamond proxy and invokes Superform/Curve contracts directly
 */
contract TestSwapIntegration is SuperformIntegrationFacet, CurveIntegrationFacet {
    using SafeERC20 for IERC20;
    using CurrencyHandler for Currency;

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

        // init Superform and Curve storage
        LibSuperform.init(superformFactory_, superformRouter_, superPositions_);
        LibCurve.init(curveRouter_);
    }

    /* ========== Test Functions ========== */

    function allocate(address strategy, uint256 amount) external returns (uint256 allocation) {
        Currency memory stakeCurrency = IStrategy(strategy).stakeCurrency();
        address revenueAsset = IStrategy(strategy).revenueAsset();

        // fetch stake to this contract
        stakeCurrency.transferFrom(msg.sender, address(this), amount);

        // allocation
        allocation = IStrategy(strategy).allocate(amount, msg.sender);

        // send asset to the user
        IERC20(revenueAsset).safeTransfer(msg.sender, allocation);
    }

    function exit(address strategy, uint256 amount) external returns (uint256 exitStake) {
        Currency memory stakeCurrency = IStrategy(strategy).stakeCurrency();
        address revenueAsset = IStrategy(strategy).revenueAsset();

        // fetch asset to this contract
        IERC20(revenueAsset).transferFrom(msg.sender, address(this), amount);

        // exit
        exitStake = IStrategy(strategy).exit(amount, msg.sender);

        // send stake to the user
        stakeCurrency.transfer(msg.sender, exitStake);
    }
}
