// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

// solhint-disable func-name-mixedcase

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurvePoolMinimal} from "../interfaces/ICurvePoolMinimal.sol";


/**
 * @title MockCurvePool (USDC <-> USDT only)
 * @notice Mock pool with exactly 2 coins: coins(1)=USDC, coins(2)=USDT,
 * @dev Applies a fixed `rate` with configurable slippage (in bps).
 */
contract MockCurvePool is ICurvePoolMinimal {
    using SafeERC20 for IERC20;

    /// @dev immutable tokens
    IERC20 public immutable USDC;
    IERC20 public immutable USDT;

    /// @dev 18-dec rate multiplier (1e18 = 100 %)
    uint256 public rate = 1e18; // 1:1 by default

    /// @dev Slippage tolerance in basis points (0–10 000)
    uint16 public slippageBps;

    uint256 public lastDy;

    // ========= Errors ========= //

    error BadIndex(uint256 index);
    error BadPair(int128 i, int128 j);

    error InsufficientLiquidity(address token, uint256 wanted, uint256 available);
    error SlippageTooHigh(uint16 bps);

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
        dy = _quoteDy(inAmount);

        uint256 bal = outTok.balanceOf(address(this));
        if (bal < dy) revert InsufficientLiquidity(address(outTok), dy, bal);

        outTok.safeTransfer(msg.sender, dy);
        lastDy = dy;
    }

    /// @dev Change rate (18 dec)
    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    /// @notice Set slippage tolerance in basis points (max 100%)
    function setSlippage(uint16 bps_) external {
        if (bps_ > 10_000) revert SlippageTooHigh(bps_);
        slippageBps = bps_;
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
    ) external view override returns (uint256 dy) {
        // i=1 -> USDC, i=2 -> USDT
        if (!((i == 1 && j == 2) || (i == 2 && j == 1)))
            revert BadPair(i, j);

        dy = _quoteDy(inAmount);
    }

    /// @notice Reverse-quote: how much input is needed for `outAmount`
    function get_dx(
        int128 i,
        int128 j,
        uint256 outAmount
    ) external view returns (uint256 dx) {
        if (!((i == 1 && j == 2) || (i == 2 && j == 1))) revert BadPair(i, j);
        // dx = outAmount * 1e18 / effectiveRate
        uint256 effRate = (rate * (10_000 - slippageBps)) / 10_000;
        dx = (outAmount * 1e18 + effRate - 1) / effRate; // round up
    }

    // ========= Interanl ========= //

    /// @notice get_dy helper
    /// @dev Applies rate and slippage
    function _quoteDy(uint256 amount_) internal view returns (uint256) {
        uint256 effRate = (rate * (10_000 - slippageBps)) / 10_000;
        return (amount_ * effRate) / 1e18;
    }
}
