// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IEmaPricing} from "../interfaces/IEmaPricing.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";
import {LibEmaPriceAnchor, Anchor} from "../../shared/libraries/LibEmaPriceAnchor.sol";

/**
 * @title EmaPricingFacet
 * @notice Diamond facet for EMA-based price protection
 * @dev Provides configuration and view functions for EMA price anchors
 *      Used by integrations (Curve, etc.) for MEV protection
 */
contract EmaPricingFacet is IEmaPricing, HyperStakingAcl {

    //============================================================================================//
    //                                      Configuration                                         //
    //============================================================================================//

    /// @inheritdoc IEmaPricing
    function configureEmaPair(
        address tokenIn,
        address tokenOut,
        bool enabled,
        uint16 deviationBps,
        uint16 emaAlphaBps,
        uint256 volumeThreshold
    ) external onlyStrategyManager {
        LibEmaPriceAnchor.configure(
            tokenIn,
            tokenOut,
            enabled,
            deviationBps,
            emaAlphaBps,
            volumeThreshold
        );
    }

    /// @inheritdoc IEmaPricing
    function setEmaPairEnabled(
        address tokenIn,
        address tokenOut,
        bool enabled
    ) external onlyStrategyManager {
        LibEmaPriceAnchor.setEnabled(tokenIn, tokenOut, enabled);
    }

    /// @inheritdoc IEmaPricing
    function setEmaDeviation(
        address tokenIn,
        address tokenOut,
        uint16 deviationBps
    ) external onlyStrategyManager {
        LibEmaPriceAnchor.setDeviationBps(tokenIn, tokenOut, deviationBps);
    }

    /// @inheritdoc IEmaPricing
    function setEmaAlpha(
        address tokenIn,
        address tokenOut,
        uint16 emaAlphaBps
    ) external onlyStrategyManager {
        LibEmaPriceAnchor.setEmaAlphaBps(tokenIn, tokenOut, emaAlphaBps);
    }

    /// @inheritdoc IEmaPricing
    function setEmaVolumeThreshold(
        address tokenIn,
        address tokenOut,
        uint256 volumeThreshold
    ) external onlyStrategyManager {
        LibEmaPriceAnchor.setVolumeThreshold(tokenIn, tokenOut, volumeThreshold);
    }

    //============================================================================================//
    //                                            Views                                           //
    //============================================================================================//

    /// @inheritdoc IEmaPricing
    function getEmaAnchor(
        address tokenIn,
        address tokenOut
    ) external view returns (Anchor memory) {
        return LibEmaPriceAnchor.getAnchor(tokenIn, tokenOut);
    }

    /// @inheritdoc IEmaPricing
    function isEmaInitialized(
        address tokenIn,
        address tokenOut
    ) external view returns (bool) {
        return LibEmaPriceAnchor.isInitialized(tokenIn, tokenOut);
    }
}
