// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Anchor} from "../../shared/libraries/LibEmaPriceAnchor.sol";

interface IEmaPricing {
    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /// @notice Configure EMA protection for a token pair
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param enabled Whether protection is active
    /// @param deviationBps Maximum allowed deviation from EMA (basis points)
    /// @param emaAlphaBps Weight for new price observations (basis points)
    /// @param volumeThreshold Minimum trade size to update EMA (in tokenIn decimals)
    function configureEmaPair(
        address tokenIn,
        address tokenOut,
        bool enabled,
        uint16 deviationBps,
        uint16 emaAlphaBps,
        uint256 volumeThreshold
    ) external;

    /// @notice Enable or disable EMA protection for a pair
    function setEmaPairEnabled(
        address tokenIn,
        address tokenOut,
        bool enabled
    ) external;

    /// @notice Update deviation tolerance for a pair
    function setEmaDeviation(
        address tokenIn,
        address tokenOut,
        uint16 deviationBps
    ) external;

    /// @notice Update EMA alpha (weight for new observations)
    function setEmaAlpha(
        address tokenIn,
        address tokenOut,
        uint16 emaAlphaBps
    ) external;

    /// @notice Update volume threshold for a pair
    function setEmaVolumeThreshold(
        address tokenIn,
        address tokenOut,
        uint256 volumeThreshold
    ) external;

    //============================================================================================//
    //                                            View                                            //
    //============================================================================================//

    /// @notice Get EMA anchor data for a token pair
    function getEmaAnchor(
        address tokenIn,
        address tokenOut
    ) external view returns (Anchor memory);

    /// @notice Check if EMA is initialized for a pair
    function isEmaInitialized(
        address tokenIn,
        address tokenOut
    ) external view returns (bool);
}
