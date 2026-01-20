// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {LibEmaPriceAnchor, Anchor} from "../shared/libraries/LibEmaPriceAnchor.sol";

/**
 * @title TestEmaPriceAnchor
 * @notice Simple proxy contract for testing LibEmaPriceAnchor in isolation
 */
contract TestEmaPriceAnchor {
    // Expose all library functions
    function configure(
        address tokenIn,
        address tokenOut,
        bool enabled,
        uint16 deviationBps,
        uint16 emaAlphaBps,
        uint256 volumeThreshold
    ) external {
        LibEmaPriceAnchor.configure(
            tokenIn,
            tokenOut,
            enabled,
            deviationBps,
            emaAlphaBps,
            volumeThreshold
        );
    }

    function setEnabled(address tokenIn, address tokenOut, bool enabled) external {
        LibEmaPriceAnchor.setEnabled(tokenIn, tokenOut, enabled);
    }

    function guardedOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 spotOut,
        uint16 slippageBps
    ) external view returns (uint256) {
        return LibEmaPriceAnchor.guardedOut(
            tokenIn,
            tokenOut,
            amountIn,
            spotOut,
            slippageBps
        );
    }

    function recordExecution(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) external {
        LibEmaPriceAnchor.recordExecution(tokenIn, tokenOut, amountIn, amountOut);
    }

    function getAnchor(address tokenIn, address tokenOut) external view returns (Anchor memory) {
        return LibEmaPriceAnchor.getAnchor(tokenIn, tokenOut);
    }

    function isInitialized(address tokenIn, address tokenOut) external view returns (bool) {
        return LibEmaPriceAnchor.isInitialized(tokenIn, tokenOut);
    }

    function isEnabled(address tokenIn, address tokenOut) external view returns (bool) {
        return LibEmaPriceAnchor.isEnabled(tokenIn, tokenOut);
    }
}
