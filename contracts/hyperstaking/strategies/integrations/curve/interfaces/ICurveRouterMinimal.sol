// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

// solhint-disable func-name-mixedcase
// solhint-disable var-name-mixedcase

/**
 * @title Curve Router v1.1 – Minimal Solidity Interface
 * @notice 3-function surface (quote-in, quote-out, swap)
 */
interface ICurveRouterMinimal {
    /**
     * @notice Execute a multi-hop swap
     * @param route Token–pool–token … sequence; unused slots = address(0)
     * @param swap_params Per-hop params: [i, j, swapType, poolType, nCoins]
     * @param amount Amount of the first token sent
     * @param min_dy Minimum final-token amount accepted
     * @param pools Extra pool addresses for factory-zap hops (otherwise zero)
     * @param receiver Address that receives the final tokens
     * @return dy Expected amount of the final output token
     */
    function exchange(
        address[11] calldata route,
        uint256[5][5] calldata swap_params,
        uint256 amount,
        uint256 min_dy,
        address[5] calldata pools,
        address receiver
    ) external payable returns (uint256 dy);

    /**
     * @notice Quote the final-token amount for a given input amount
     * @return dy Estimated final-token amount
     */
    function get_dy(
        address[11] calldata route,
        uint256[5][5] calldata swap_params,
        uint256 amount,
        address[5] calldata pools
    ) external view returns (uint256 dy);

    /**
     * @notice Quote the input amount needed to obtain `out_amount` final tokens
     * @return dx Required amount of input token to send.
     */
    function get_dx(
        address[11] calldata route,
        uint256[5][5] calldata swap_params,
        uint256 out_amount,
        address[5] calldata pools,
        address[5] calldata base_pools,
        address[5] calldata base_tokens
    ) external view returns (uint256 dx);
}
