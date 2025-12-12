// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

// solhint-disable func-name-mixedcase

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurvePoolMinimal} from "../interfaces/ICurvePoolMinimal.sol";


/**
 * @title MockCurvePool (USDC <-> USDT only)
 * @notice Mock pool with exactly 2 coins: coins(1)=USDC, coins(2)=USDT,
 * @dev Applies a fixed `rate` to simulate slippage
 */
contract MockCurvePool is ICurvePoolMinimal {
    using SafeERC20 for IERC20;

    /// @dev immutable tokens
    IERC20 public immutable USDC;
    IERC20 public immutable USDT;

    /// @dev 18-dec rate multiplier (1e18 = 100 %)
    ///      1:1 by default,
    ///      1:1 is also used for quote to simulate slippage
    uint256 public rate = 1e18;

    uint256 public lastDy;

    // ========= Errors ========= //

    error BadIndex(uint256 index);
    error BadPair(int128 i, int128 j);

    error InsufficientLiquidity(address token, uint256 wanted, uint256 available);

    // ========= Constructor ========= //

    constructor(address usdc, address usdt) {
        USDC = IERC20(usdc);
        USDT = IERC20(usdt);
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc ICurvePoolMinimal
    function exchange(
        int128 i,
        int128 j,
        uint256 inAmount,
        uint256 /*min_dy*/
    ) external override returns (uint256 dy) {
        // pull & push exactly like real pool
        IERC20 inTok  = i == 1 ? USDC : (i == 2 ? USDT : IERC20(address(0)));
        IERC20 outTok = j == 2 ? USDT : (j == 1 ? USDC : IERC20(address(0)));
        if (
            i == j ||
            address(inTok) == address(0) ||
            address(outTok) == address(0)
        ) revert BadPair(i, j);

        // actual exchange
        inTok.safeTransferFrom(msg.sender, address(this), inAmount);

        dy = realDy(inAmount);

        uint256 bal = outTok.balanceOf(address(this));
        if (bal < dy) revert InsufficientLiquidity(address(outTok), dy, bal);

        outTok.safeTransfer(msg.sender, dy);
        lastDy = dy;
    }

    /// @dev Change rate (18 dec)
    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    // ========= View ========= //

    /// @inheritdoc ICurvePoolMinimal
    function coins(uint256 index) external view override returns (address) {
        if (index == 1) return address(USDC);
        if (index == 2) return address(USDT);
        revert BadIndex(index);
    }

    /// @inheritdoc ICurvePoolMinimal
    function get_dy(
        int128 i,
        int128 j,
        uint256 inAmount
    ) external pure override returns (uint256 dy) {
        // i=1 -> USDC, i=2 -> USDT
        if (!((i == 1 && j == 2) || (i == 2 && j == 1)))
            revert BadPair(i, j);

        dy = inAmount;
    }

    /// @notice Reverse-quote: how much input is needed for `outAmount`
    /// @dev always 1:1
    function get_dx(
        int128 i,
        int128 j,
        uint256 outAmount
    ) external pure returns (uint256 dx) {
        // i=1 -> USDC, i=2 -> USDT
        if (!((i == 1 && j == 2) || (i == 2 && j == 1)))
            revert BadPair(i, j);

        dx = outAmount;
    }

    /// @notice helper
    /// @dev Applies rate
    function realDy(uint256 inAmount) public view returns (uint256) {
        return (inAmount * rate) / 1e18;
    }

    /// @notice helper
    /// @dev Applies rate
    function realDx(uint256 outAmount) public view returns (uint256) {
        return (outAmount * 1e18 + rate - 1) / rate; // round up
    }
}
