// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../interfaces/IStrategy.sol";
import {AbstractStrategy} from "./AbstractStrategy.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";

/**
 * @title DirectStakeStrategy
 * @notice A placeholder strategy used for direct deposits without yield generation
 *         It stores currency informationm but, exists primarily to maintain compatibility
 *         with the vault structure and will revert on the majority of function calls
 */
contract DirectStakeStrategy is AbstractStrategy {
    using CurrencyHandler for Currency;

    /// Main currency used for staking
    Currency private currency;

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error DirectStakeMisused();

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
    function allocate(uint256, address) external payable returns (uint256) {
        revert DirectStakeMisused();
    }

    /// @inheritdoc IStrategy
    function exit(uint256, address) external pure returns (uint256) {
        revert DirectStakeMisused();
    }

    // ========= View ========= //

    /// @inheritdoc IStrategy
    function isDirectStakeStrategy() external pure virtual override returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function stakeCurrency() external view returns(Currency memory) {
        return currency;
    }

    /// @inheritdoc IStrategy
    function revenueAsset() external pure returns(address) {
        revert DirectStakeMisused();
    }

    /// Price = 1:1
    function previewAllocation(uint256) public pure returns (uint256) {
        revert DirectStakeMisused();
    }

    /// Price = 1:1
    function previewExit(uint256) public pure returns (uint256) {
        revert DirectStakeMisused();
    }
}
