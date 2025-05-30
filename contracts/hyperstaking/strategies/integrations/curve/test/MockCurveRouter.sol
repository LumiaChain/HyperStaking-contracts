// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

// solhint-disable func-name-mixedcase

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICurveRouterMinimal} from "../interfaces/ICurveRouterMinimal.sol";
import {ICurvePoolMinimal} from "../interfaces/ICurvePoolMinimal.sol";
import {MockCurvePool} from "./MockCurvePool.sol";

/**
 * @title MockCurveRouter (USDT <-> USDC only)
 * @notice Transfers real ERC20 tokens, reverts if the pool’s balance can’t cover the output side
 */
contract MockCurveRouter is ICurveRouterMinimal {
    using SafeERC20 for IERC20;

    /// @dev helpers for assertions
    uint256 public lastAmountIn;
    uint256 public lastAmountOut;

    // ========= Errors ========= //

    error ZeroReceiver();
    error Slippage();
    error UnsupportedRoute();

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @notice Single-hop mock. Direction comes from `route`:
    ///         `route[0]` the input token and `route[2]` the output token
    /// @dev Supports USDT <-> USDC only
    function exchange(
        address[11] calldata route,
        uint256[5][5] calldata,   // swap_params ignored in mock
        uint256 amount,
        uint256 minDy,
        address[5] calldata,      // pools ignored
        address receiver
    ) external payable override returns (uint256 dy) {
        require(receiver != address(0), ZeroReceiver());

        address tokenIn = route[0];
        address pool = route[1];
        address tokenOut = route[2];

        // pull + approve
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(tokenIn).safeIncreaseAllowance(pool, amount);

        // compute indexes & quote
        int128 i = _coinIndex(pool, tokenIn);
        int128 j = _coinIndex(pool, tokenOut);

        // get the quote
        dy = MockCurvePool(pool).realDy(amount);
        require(dy >= minDy, Slippage());

        // execute & forward
        ICurvePoolMinimal(pool).exchange(i, j, amount, minDy);
        IERC20(tokenOut).safeTransfer(receiver, dy);

        lastAmountIn  = amount;
        lastAmountOut = dy;
    }

    // ========= View ========= //

    /// @dev Quote output for a given input
    function get_dy(
        address[11] calldata route,
        uint256[5][5] calldata,
        uint256 amount,
        address[5] calldata
    ) public view override returns (uint256 dy) {
        address pool = route[1];
        int128 i = _coinIndex(pool, route[0]);
        int128 j = _coinIndex(pool, route[2]);
        dy = ICurvePoolMinimal(pool).get_dy(i, j, amount);
    }

    /// @dev Quote input required for a desired output
    function get_dx(
        address[11] calldata route,
        uint256[5][5] calldata,
        uint256 outAmount,
        address[5] calldata,
        address[5] calldata,
        address[5] calldata
    ) public view override returns (uint256 dx) {
        address pool = route[1];
        int128 i = _coinIndex(pool, route[0]);
        int128 j = _coinIndex(pool, route[2]);

        // use MockCurveRouter as ICurvePool does not contain get_dx
        dx = MockCurvePool(pool).get_dx(i, j, outAmount);
    }

    // ========= Interanl ========= //

    /// @dev USDC is index 1, USDT is index 2. Reverts otherwise
    function _coinIndex(address pool, address token) private view returns (int128) {
        if (token == ICurvePoolMinimal(pool).coins(1)) return int128(1);
        if (token == ICurvePoolMinimal(pool).coins(2)) return int128(2);
        revert UnsupportedRoute();
    }
}
