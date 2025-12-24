// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {StrategyKind, StrategyRequest, IStrategy} from "../interfaces/IStrategy.sol";
import {AbstractStrategy} from "./AbstractStrategy.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PirexIntegration} from "./integrations/PirexIntegration.sol";

import {Currency} from "../../shared/libraries/CurrencyHandler.sol";

/**
 * @title DineroStrategy
 * @notice This contract manages liquidity staking the base (ETH) asset in Pirex protocol
 */
contract DineroStrategy is AbstractStrategy, PirexIntegration {
    using SafeERC20 for IERC20;

    /// Storage gap for upgradeability. Must remain the last state variable
    uint256[50] private __gap;

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error BadAllocationValue();

    //============================================================================================//
    //                                        Initialize                                          //
    //============================================================================================//

    function initialize (
        address diamond_,
        address pxEth_,
        address pirexEth_,
        address autoPxEth_
    ) public initializer {
        __AbstractStrategy_init(diamond_);
        __PirexIntegration_init(pxEth_, pirexEth_, autoPxEth_);
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Diamond ========= //

    /// @inheritdoc IStrategy
    function requestAllocation(
        uint256 requestId_,
        uint256 amount_,
        address user_
    ) external payable onlyLumiaDiamond returns (uint64 readyAt) {
        require(amount_ == msg.value, BadAllocationValue());

        readyAt = previewAllocationReadyAt(amount_);
        _storeAllocationRequest(
            requestId_,
            user_,
            amount_,
            readyAt
        );

        emit AllocationRequested(requestId_, user_, amount_, readyAt);
    }

    /// @inheritdoc IStrategy
    function claimAllocation(
        uint256[] calldata ids_, address receiver_
    ) external onlyLumiaDiamond returns (uint256 allocation) {
        require(ids_.length == 1, DontSupportArrays());
        uint256 id = ids_[0];

        StrategyRequest memory r = _loadClaimable(id, StrategyKind.Allocation);
        _markClaimed(id);

        // mint apx for Diamond
        allocation = depositCompound(receiver_, r.amount);

        emit AllocationClaimed(id, receiver_, allocation);
    }

    /// @inheritdoc IStrategy
    function requestExit(
        uint256 requestId_,
        uint256 shares_,
        address user_
    ) external onlyLumiaDiamond returns (uint64 readyAt) {
        IERC20(AUTO_PX_ETH).safeTransferFrom(DIAMOND, address(this), shares_);

        readyAt = previewExitReadyAt(shares_);
        _storeExitRequest(
            requestId_,
            user_,
            shares_,
            readyAt
        );

        emit ExitRequested(requestId_, user_, shares_, readyAt);
    }

    /// @inheritdoc IStrategy
    function claimExit(
        uint256[] calldata ids_, address receiver_
    ) external onlyLumiaDiamond returns (uint256 exitAmount) {
        require(ids_.length == 1, DontSupportArrays());
        uint256 id = ids_[0];

        StrategyRequest memory r = _loadClaimable(id, StrategyKind.Exit);
        _markClaimed(id);

        // transfer stake amount back to the Diamond
        exitAmount = redeem(r.amount, receiver_);

        emit ExitClaimed(id, receiver_, exitAmount);
    }

    // ========= View ========= //

    /// @inheritdoc IStrategy
    function stakeCurrency() external pure returns(Currency memory) {
        return Currency({
            token: address(0)
        });
    }

    /// @inheritdoc IStrategy
    function revenueAsset() external view returns(address) {
        return AUTO_PX_ETH;
    }

    /// @inheritdoc IStrategy
    function previewAllocationReadyAt(uint256) public pure returns (uint64 readyAt) {
        readyAt = 0; // claimable immediately -> sync deposit flow
    }

    /// @inheritdoc IStrategy
    function previewExitReadyAt(uint256) public pure returns (uint64 readyAt) {
        readyAt = 0; // claimable immediately -> sync redeem flow
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// Return current stake to asset ratio (eth/apxEth price)
    function _previewAllocationRaw(uint256 stake_) internal view override returns (uint256) {
        return _convertEthToApxEth(stake_);
    }

    /// Return current asset to stake ratio (apxEth/eth price)
    function _previewExitRaw(uint256 allocation_) internal view override returns (uint256) {
        return _convertApxEthToEth(allocation_);
    }
}
