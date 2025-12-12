// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

// solhint-disable func-name-mixedcase
// solhint-disable var-name-mixedcase

/**
 * @title Curve StableSwap Minimal Interface
 * @notice Tiny ABI surface—quote + swap functions for StableSwap-style pool
 */
interface ICurvePoolMinimal {
    /**
     * @notice Swap `in_amount` of coin `i` for at least `min_dy` of coin `j`
     *
     * @dev NOTE: The original Ethereum-mainnet 3Pool (0xbEbc..., Vyper 0.2.4)
     *      declares `exchange(int128,int128,uint256,uint256)` **without** a return value
     *      Calling it through an interface that expects `returns (uint256)` will revert
     *
     * @param i Index of the input coin
     * @param j Index of the output coin
     * @param in_amount Amount of coin `i` to swap
     * @param min_dy Minimum acceptable amount of coin `j`; reverts if not met
     * @return dy Actual output amount of coin `j`
     */
    function exchange(
        int128 i,
        int128 j,
        uint256 in_amount,
        uint256 min_dy
    ) external returns (uint256 dy);

    /**
     * @notice Returns the token address at a given coin index in the pool.
     * @param index Zero-based coin position (0, 1, 2 …).
     * @return token Address of the coin stored at that index.
     */
    function coins(uint256 index) external view returns (address);

    /**
     * @notice Quote how many units of coin `j` you’ll receive for `in_amount` of coin `i`
     * @param i Index of the input coin
     * @param j Index of the output coin
     * @param in_amount Amount of coin `i` to swap
     * @return dy Estimated output amount of coin `j`
     */
    function get_dy(
        int128 i,
        int128 j,
        uint256 in_amount
    ) external view returns (uint256 dy);
}
