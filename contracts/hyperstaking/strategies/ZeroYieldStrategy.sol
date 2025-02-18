// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../interfaces/IStrategy.sol";
import {AbstractStrategy} from "./AbstractStrategy.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";

/**
 * @title ZeroYieldStrategy
 * @notice A simple strategy that allows to stake and allocate with the same currency
 */
contract ZeroYieldStrategy is AbstractStrategy {
    using CurrencyHandler for Currency;

    /// Main currency used both as stake and allocation
    Currency public currency;

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    constructor(
        address diamond_,
        Currency memory currency_
    ) AbstractStrategy(diamond_) {
        currency = currency_;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IStrategy
    function allocate(
        uint256 stakeAmount_,
        address user_
    ) external payable onlyLumiaDiamond returns (uint256 allocation) {
        allocation = stakeAmount_; // the same amount

        currency.transferFrom(DIAMOND, address(this), stakeAmount_);

        if (currency.isNativeCoin()) {
            currency.transfer(DIAMOND, allocation);
        } else {
            currency.approve(DIAMOND, allocation);
        }

        emit Allocate(user_, stakeAmount_, allocation);
    }


    /// @inheritdoc IStrategy
    function exit(
        uint256 assetAllocation_,
        address user_
    ) external onlyLumiaDiamond returns (uint256 exitAmount) {
        exitAmount = assetAllocation_; // the same amount

        currency.transferFrom(DIAMOND, address(this), assetAllocation_);
        currency.transfer(DIAMOND, exitAmount);

        emit Exit(user_, assetAllocation_, exitAmount);
    }

    // ========= View ========= //

    /// @inheritdoc IStrategy
    function stakeCurrency() external view returns(Currency memory) {
        return currency;
    }

    /// @inheritdoc IStrategy
    function revenueAsset() external view returns(address) {
        return currency.token;
    }

    /// Price = 1:1
    function previewAllocation(uint256 stakeAmount_) public pure returns (uint256) {
        return stakeAmount_;
    }

    /// Price = 1:1
    function previewExit(uint256 assetAllocation_) public pure returns (uint256) {
        return assetAllocation_;
    }
}
