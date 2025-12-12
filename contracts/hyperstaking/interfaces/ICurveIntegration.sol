// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/**
 * @title ICurveIntegration
 * @notice Minimal one-hop wrapper around Curve Router
 *         – quote the output of a single pool swap,
 *         – execute the swap and forward the proceeds
 */
interface ICurveIntegration {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event CurveRouterUpdated(address newRouter);
    event SwapStrategyUpdated(address strategy, bool status);
    event PoolRegistered(address pool, uint8 nCoins);

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error NotFromSwapStrategy(address);

    error SameCoinSwap();
    error CoinNotInPool();

    error PoolSizeMismatch();
    error PoolBadNCoins();
    error PoolDuplicateToken();

    error TokenNotRegistered(address);
    error PoolNotRegistered();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @dev Executes the swap exchange and forwards the output to `receiver`
     * @param tokenIn Token supplied to the pool
     * @param pool Curve pool used for the trade
     * @param tokenOut Token expected from the swap
     * @param amountIn Amount of `tokenIn` to swap
     * @param minDy Minimum acceptable `tokenOut`; revert on slippage
     * @param receiver Address receiving `tokenOut`
     * @return dy Amount actually received
     */
    function swap(
        address tokenIn,
        address pool,
        address tokenOut,
        uint256 amountIn,
        uint256 minDy,
        address receiver
    ) external returns (uint256 dy);

    /// @notice Points the facet to a new Curve Router address
    function updateCurveRouter(address newRouter) external;

    /// @notice Updates the status of a Swap strategy
    function updateSwapStrategies(address strategy, bool status) external;

    /**
     * @notice Register a pool
     * @param pool Curve pool address (e.g. 3Pool)
     * @param nCoins Total coins in the pool
     * @param tokens Coin addresses in any order
     * @param indexes Corresponding indexes for each token
     */
    function registerPool(
        address pool,
        uint8 nCoins,
        address[] calldata tokens,
        uint8[] calldata indexes
    ) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /**
     * @dev Read-only quote
     * @param tokenIn Token supplied to the pool
     * @param pool Curve pool that holds both coins
     * @param tokenOut Token expected from the swap
     * @param amountIn Amount of `tokenIn` to be swapped (token decimals)
     * @return dy Estimated amount of `tokenOut`
     */
    function quote(
        address tokenIn,
        address pool,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 dy);

    /// @notice Curve Router address currently used for swaps
    function curveRouter() external view returns (address);

    /// @notice Whitelisted swap-strategy address stored at `index`
    function swapStrategyAt(uint256 index) external view returns (address);

    /// @notice Total number of whitelisted swap strategies
    function swapStrategiesLength() external view returns (uint256);

    /// @notice Registered data for a pool — token list and indexes
    function poolConfig(
        address pool
    ) external view returns (address[] memory tokens, uint8[] memory indexes);
}
