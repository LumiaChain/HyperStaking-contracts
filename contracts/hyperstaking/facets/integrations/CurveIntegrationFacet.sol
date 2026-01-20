// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {ICurveIntegration} from "../../interfaces/ICurveIntegration.sol";
import {HyperStakingAcl} from "../../HyperStakingAcl.sol";

import {LibCurve, CurveStorage, PoolConfig} from "../../libraries/LibCurve.sol";
import {IEmaPricing} from "../../interfaces/IEmaPricing.sol";

import {ICurveRouterMinimal} from "../../strategies/integrations/curve/interfaces/ICurveRouterMinimal.sol";


import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LibEmaPriceAnchor} from "../../../shared/libraries/LibEmaPriceAnchor.sol";
import * as Errors from "../../../shared/Errors.sol";

/**
 * @title CurveIntegration
 * @dev Diamond facet that wraps a single-hop Curve Router call
 *      – Manager registers static pool layouts (coin indices + nCoins)
 *      – Strategies call {quote} and {swap} for fast USDT <-> USDC - style trades
 */
contract CurveIntegrationFacet is ICurveIntegration, HyperStakingAcl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    /// @notice Only accept messages from swap (curve) strategies
    modifier onlySwapStrategy() {
        CurveStorage storage s = LibCurve.diamondStorage();

        require(s.swapStrategies.contains(msg.sender), NotFromSwapStrategy(msg.sender));
        _;
    }

    /// @notice Requires Curve router to be configured
    modifier requireRouter() {
        LibCurve.requireRouter();
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /* ========== Strategy ========== */

    /// @inheritdoc ICurveIntegration
    function swap(
        address tokenIn,
        address pool,
        address tokenOut,
        uint256 amountIn,
        uint256 minDy,
        address receiver
    ) external onlySwapStrategy requireRouter returns (uint256 dy) {
        ICurveRouterMinimal router = LibCurve.diamondStorage().curveRouter;

        (
            address[11] memory route,
            uint256[5][5] memory params,
            address[5] memory blank
        ) = _buildCalldata(tokenIn, pool, tokenOut);

        // curve router exchange
        IERC20(tokenIn).safeIncreaseAllowance(address(router), amountIn);
        dy = router.exchange(
            route,
            params,
            amountIn,
            minDy,
            blank,
            receiver
        );

        // record execution for EMA
        LibEmaPriceAnchor.recordExecution(tokenIn, tokenOut, amountIn, dy);
    }

    /* ========== Strategy Manager ========== */

    /// @inheritdoc ICurveIntegration
    function setCurveRouter(address newRouter) external onlyStrategyManager {
        LibCurve.setRouter(newRouter);

        emit CurveRouterUpdated(newRouter);
    }

    /// @inheritdoc ICurveIntegration
    function updateSwapStrategies(
        address strategy,
        bool status
    ) external onlyStrategyManager requireRouter {
        CurveStorage storage s = LibCurve.diamondStorage();

        // EnumerableSet returns a boolean indicating success
        if (status) {
            require(s.swapStrategies.add(strategy), Errors.UpdateFailed());
        } else {
            require(s.swapStrategies.remove(strategy), Errors.UpdateFailed());
        }

        emit SwapStrategyUpdated(strategy, status);
    }

    /// @inheritdoc ICurveIntegration
    function registerPool(
        address pool,
        uint8 nCoins,
        address[] calldata tokens,
        uint8[] calldata indexes
    ) external onlyStrategyManager requireRouter {
        require(tokens.length == indexes.length && tokens.length == nCoins, PoolSizeMismatch());
        require(nCoins > 1 && nCoins <= 8, PoolBadNCoins());

        PoolConfig storage pc = LibCurve.diamondStorage().poolsConfig[pool];

        // clean previous pool storage
        uint256 tokenListLen = pc.tokenList.length; // cache array len
        for (uint256 i; i < tokenListLen; ++i) {
            delete pc.tokenIndex[pc.tokenList[i]]; // remove token index
            delete pc.tokenExists[pc.tokenList[i]]; // remove info if token exists
        }
        delete pc.tokenList; // remove token list

        for (uint256 i; i < nCoins; ++i) {
            require(!pc.tokenExists[tokens[i]], PoolDuplicateToken());
            pc.tokenList.push(tokens[i]);
            pc.tokenIndex[tokens[i]] = indexes[i];
            pc.tokenExists[tokens[i]] = true;
        }

        emit PoolRegistered(pool, nCoins);
    }
    /// @inheritdoc ICurveIntegration
    function configureSwapStrategyEma(
        address tokenIn,
        address tokenOut,
        bool enabled,
        uint16 deviationBps,
        uint16 emaAlphaBps,
        uint256 volumeThreshold
    ) external onlySwapStrategy {
        LibEmaPriceAnchor.configure(
            tokenIn,
            tokenOut,
            enabled,
            deviationBps,
            emaAlphaBps,
            volumeThreshold
        );
    }

    // ========= View ========= //

    /// @inheritdoc ICurveIntegration
    function quote(
        address tokenIn,
        address pool,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 dy) {
        ICurveRouterMinimal router = LibCurve.diamondStorage().curveRouter;

        (
            address[11] memory route,
            uint256[5][5] memory params,
            address[5] memory blank
        ) = _buildCalldata(tokenIn, pool, tokenOut);

        dy = router.get_dy(
            route,
            params,
            amountIn,
            blank // no zap pools for one-hop
        );
    }

    /// @notice Get EMA-protected quote with slippage - use this for swaps
    /// @param slippageBps Slippage tolerance in basis points
    /// @return minDy Protected minimum output with slippage applied
    function quoteProtected(
        address tokenIn,
        address pool,
        address tokenOut,
        uint256 amountIn,
        uint16 slippageBps
    ) external view returns (uint256 minDy) {
        // Get raw spot quote from Curve
        uint256 spotQuote = this.quote(tokenIn, pool, tokenOut, amountIn);

        // Apply EMA protection + slippage
        minDy = LibEmaPriceAnchor.guardedOut(
            tokenIn,
            tokenOut,
            amountIn,
            spotQuote,
            slippageBps
        );
    }

    /// @inheritdoc ICurveIntegration
    function curveRouter() external view returns (address) {
        return address(LibCurve.diamondStorage().curveRouter);
    }

    /// @inheritdoc ICurveIntegration
    function swapStrategyAt(uint256 index) external view returns (address) {
        return LibCurve.diamondStorage().swapStrategies.at(index);
    }

    /// @inheritdoc ICurveIntegration
    function swapStrategiesLength() external view returns (uint256) {
        return LibCurve.diamondStorage().swapStrategies.length();
    }

    function poolConfig(
        address pool
    ) external view returns (address[] memory tokens, uint8[] memory indexes) {
        PoolConfig storage pc = LibCurve.diamondStorage().poolsConfig[pool];
        tokens = pc.tokenList;

        indexes = new uint8[](tokens.length);
        uint256 tokensLen = tokens.length; // cache array len
        for (uint256 i; i < tokensLen; ++i) {
            indexes[i] = pc.tokenIndex[tokens[i]];
        }
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @dev Returns the registered index of `token` in `pool`; reverts if not set
    function _coinIndex(address pool, address token) internal view returns (uint8) {
        PoolConfig storage pc = LibCurve.diamondStorage().poolsConfig[pool];

        require(pc.tokenExists[token], TokenNotRegistered(token));
        return pc.tokenIndex[token];
    }

    /// @dev Returns the coin count for `pool`; reverts if unregistered
    function _nCoins(address pool) internal view returns (uint8) {
        uint8 n = uint8(LibCurve.diamondStorage().poolsConfig[pool].tokenList.length);
        require(n != 0, PoolNotRegistered());
        return n;
    }

    /// @dev Builds Router calldata for *one* hop. Finds coin indices on-chain
    function _buildCalldata(
        address tokenIn,
        address pool,
        address tokenOut
    )
        private
        view
        returns (
            address[11] memory route,
            uint256[5][5] memory params,
            address[5] memory pools // all-zero array
        )
    {
        require(tokenIn != tokenOut, SameCoinSwap());

        // route (t-p-t)
        route[0] = tokenIn;
        route[1] = pool;
        route[2] = tokenOut;

        uint256 nCoins = _nCoins(pool);

        // coin indices inside the pool
        uint256 i = _coinIndex(pool, tokenIn);
        uint256 j = _coinIndex(pool, tokenOut);
        require(i != type(uint256).max && j != type(uint256).max, CoinNotInPool());

        // params[0] = [i, j, swapType(1), poolType(1), nCoins]
        params[0][0] = i;
        params[0][1] = j;
        params[0][2] = 1; // swap_type == exchange
        params[0][3] = 1; // pool_type == stable
        params[0][4] = nCoins;
        // rest already zero

        // pools for swaps via zap (only for swapType == 3)
        address[5] memory blank; // zeros array
        pools = blank;
    }
}
