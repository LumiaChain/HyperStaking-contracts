// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/**
 * @notice EMA price anchor guardrail for execution-time quotes with MEV protection
 * @dev Stores per-pair EMA price ratio (tokenOut per tokenIn) as 18-dec fixed point
 *      Amounts keep original decimals, emaPrice is always 18-dec
 *
 * Philosophy:
 * - EMA is the primary reference price for execution bounds
 * - Spot quotes are only used as a signal and are clamped to an EMA deviation band
 * - Anchor is updated only from realized executions (amountIn/amountOut)
 * - Updates are volume-weighted to resist manipulation via many small trades
 *
 * Intentional design decisions:
 * - First execution has no protection (bootstrap phase, accepted risk)
 * - No staleness checks (would require external price monitoring)
 * - Future upgrade: add staleness threshold + external price oracle fallback
 *
 * emaAlphaBps examples:
 * - 200  => 2% new, 98% old
 * - 1000 => 10% new, 90% old
 * - 5000 => 50% new, 50% old
 */

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct Anchor {
    address tokenIn;
    address tokenOut;
    bool enabled;
    uint16 deviationBps;  // max % deviation spot can be from EMA (e.g., 500 = 5%)
    uint16 emaAlphaBps;   // weight for new observations (e.g., 200 = 2%)
    uint64 lastUpdated;
    uint256 emaPrice;     // tokenOut per tokenIn, always 18-dec fixed point
    uint256 volumeThreshold;  // trades below this threshold dont affect ema
}

struct EmaPriceAnchorStorage {
    mapping(address => mapping(address => Anchor)) anchors;
}

library LibEmaPriceAnchor {
    bytes32 internal constant STORAGE_POSITION =
        bytes32(uint256(keccak256("lumia.ema-price-anchor-0.1.storage")) - 1);

    //================================================================================================//
    //                                            Events                                              //
    //================================================================================================//

    event EmaAnchorConfigured(
        address indexed tokenIn,
        address indexed tokenOut,
        bool enabled,
        uint16 deviationBps,
        uint16 emaAlphaBps,
        uint256 volumeThreshold
    );

    event EmaAnchorEnabled(
        address indexed tokenIn,
        address indexed tokenOut,
        bool enabled
    );

    event EmaDeviationUpdated(
        address indexed tokenIn,
        address indexed tokenOut,
        uint16 deviationBps
    );

    event EmaAlphaUpdated(
        address indexed tokenIn,
        address indexed tokenOut,
        uint16 emaAlphaBps
    );

    event EmaVolumeThresholdUpdated(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 volumeThreshold
    );

    event EmaUpdated(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 spotPrice,
        uint256 amountIn
    );

    //================================================================================================//
    //                                            Errors                                              //
    //================================================================================================//

    error BadBps(uint256 bps);
    error BadAlpha(uint256 bps);
    error BadTokens(address tokenIn, address tokenOut);
    error ZeroQuote();

    error AnchorNotConfigured(address tokenIn, address tokenOut);
    error AnchorDisabled(address tokenIn, address tokenOut);
    error AnchorAlreadyConfigured(address tokenIn, address tokenOut);

    //================================================================================================//
    //                                         Configuration                                          //
    //================================================================================================//

    function configure(
        address tokenIn,
        address tokenOut,
        bool enabled,
        uint16 deviationBps,
        uint16 emaAlphaBps,
        uint256 volumeThreshold
    ) internal {
        if (tokenIn == address(0) || tokenOut == address(0) || tokenIn == tokenOut) {
            revert BadTokens(tokenIn, tokenOut);
        }
        if (deviationBps > 10_000) {
            revert BadBps(deviationBps);
        }
        if (emaAlphaBps == 0 || emaAlphaBps > 10_000) {
            revert BadAlpha(emaAlphaBps);
        }

        Anchor storage a = _storage().anchors[tokenIn][tokenOut];

        // prevent reconfiguration of already initialized anchor
        if (a.tokenIn != address(0) && a.emaPrice != 0) {
            revert AnchorAlreadyConfigured(tokenIn, tokenOut);
        }

        a.tokenIn = tokenIn;
        a.tokenOut = tokenOut;
        a.enabled = enabled;
        a.deviationBps = deviationBps;
        a.emaAlphaBps = emaAlphaBps;
        a.volumeThreshold = volumeThreshold;

        emit EmaAnchorConfigured(
            tokenIn,
            tokenOut,
            enabled,
            deviationBps,
            emaAlphaBps,
            volumeThreshold
        );
    }

    function setEnabled(address tokenIn, address tokenOut, bool enabled) internal {
        _storage().anchors[tokenIn][tokenOut].enabled = enabled;
        emit EmaAnchorEnabled(tokenIn, tokenOut, enabled);
    }

    function setDeviationBps(address tokenIn, address tokenOut, uint16 deviationBps) internal {
        if (deviationBps > 10_000) {
            revert BadBps(deviationBps);
        }
        _storage().anchors[tokenIn][tokenOut].deviationBps = deviationBps;
        emit EmaDeviationUpdated(tokenIn, tokenOut, deviationBps);
    }

    function setEmaAlphaBps(address tokenIn, address tokenOut, uint16 emaAlphaBps) internal {
        if (emaAlphaBps == 0 || emaAlphaBps > 10_000) {
            revert BadAlpha(emaAlphaBps);
        }
        _storage().anchors[tokenIn][tokenOut].emaAlphaBps = emaAlphaBps;
        emit EmaAlphaUpdated(tokenIn, tokenOut, emaAlphaBps);
    }

    function setVolumeThreshold(address tokenIn, address tokenOut, uint256 volumeThreshold) internal {
        _storage().anchors[tokenIn][tokenOut].volumeThreshold = volumeThreshold;
        emit EmaVolumeThresholdUpdated(tokenIn, tokenOut, volumeThreshold);
    }

    //================================================================================================//
    //                                     Execution helpers                                          //
    //================================================================================================//

    /**
     * @notice Guard spot quote using EMA bounds (view only, no recording)
     * @param amountIn Input amount
     * @param spotOut Spot quote output
     * @param slippageBps Additional slippage tolerance
     * @return Protected minimum output after EMA guard + slippage
     */
    function guardedOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 spotOut,
        uint16 slippageBps
    ) internal view returns (uint256) {
        return _guard(tokenIn, tokenOut, amountIn, spotOut, slippageBps);
    }

    /**
     * @notice Update EMA from realized execution (recording only, no guard)
     * @param amountOut Realized output amount
     */
    function recordExecution(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        _record(tokenIn, tokenOut, amountIn, amountOut);
    }

    //================================================================================================//
    //                                            Views                                               //
    //================================================================================================//

    function getAnchor(address tokenIn, address tokenOut) internal view returns (Anchor memory) {
        return _storage().anchors[tokenIn][tokenOut];
    }

    function isInitialized(address tokenIn, address tokenOut) internal view returns (bool) {
        return _storage().anchors[tokenIn][tokenOut].emaPrice != 0;
    }

    //================================================================================================//
    //                                          Private                                               //
    //================================================================================================//

    function _guard(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 spotOut,
        uint16 slippageBps
    ) private view returns (uint256 out) {
        if (slippageBps > 10_000) {
            revert BadBps(slippageBps);
        }
        if (spotOut == 0) {
            revert ZeroQuote();
        }

        Anchor memory a = _storage().anchors[tokenIn][tokenOut];

        // require anchor to be configured
        if (a.tokenIn == address(0)) {
            revert AnchorNotConfigured(tokenIn, tokenOut);
        }

        // require anchor to be enabled
        if (!a.enabled) {
            revert AnchorDisabled(tokenIn, tokenOut);
        }

        if (amountIn == 0) {
            out = 0;
        } else if (a.emaPrice == 0) {
            // bootstrap: not initialized yet, return spot
            out = spotOut;
        } else {
            uint256 emaOut = (amountIn * a.emaPrice) / 1e18;
            out = _clamp(spotOut, emaOut, a.deviationBps);
        }

        if (slippageBps > 0) {
            out = (out * (10_000 - slippageBps)) / 10_000;
        }
    }

    function _record(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) private {
        Anchor storage a = _storage().anchors[tokenIn][tokenOut];

        // require anchor to be configured
        if (a.tokenIn == address(0)) {
            revert AnchorNotConfigured(tokenIn, tokenOut);
        }

        // require anchor to be enabled
        if (!a.enabled) {
            revert AnchorDisabled(tokenIn, tokenOut);
        }

        if (amountIn == 0 || amountOut == 0) {
            return;
        }

        // skip update if below volume threshold (prevents dust manipulation)
        if (a.volumeThreshold > 0 && amountIn < a.volumeThreshold) {
            return;
        }

        uint256 spotPrice = (amountOut * 1e18) / amountIn;

        if (a.emaPrice == 0) {
            a.emaPrice = spotPrice;
            a.lastUpdated = uint64(block.timestamp);
            emit EmaUpdated(tokenIn, tokenOut, 0, spotPrice, spotPrice, amountIn);
            return;
        }

        uint256 alpha = uint256(a.emaAlphaBps);
        uint256 oldPrice = a.emaPrice;
        uint256 newPrice = (oldPrice * (10_000 - alpha) + spotPrice * alpha) / 10_000;

        a.emaPrice = newPrice;
        a.lastUpdated = uint64(block.timestamp);

        emit EmaUpdated(tokenIn, tokenOut, oldPrice, newPrice, spotPrice, amountIn);
    }

    function _clamp(
        uint256 value,
        uint256 center,
        uint16 deviationBps
    ) private pure returns (uint256) {
        uint256 delta = (center * deviationBps) / 10_000;
        uint256 lo = delta > center ? 0 : center - delta; // prevent underflow
        uint256 hi = center + delta;

        // if spot within bounds
        if (value >= lo && value <= hi) {
            return value; // return spot, it's already validated as acceptable
        }

        // otherwise clamp spot to bounds
        if (value < lo) return lo;
        if (value > hi) return hi;
        return value;
    }

    function _storage() private pure returns (EmaPriceAnchorStorage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
