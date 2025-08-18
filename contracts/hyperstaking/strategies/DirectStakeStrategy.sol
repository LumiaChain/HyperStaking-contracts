// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {StrategyRequest, StrategyKind, IStrategy} from "../interfaces/IStrategy.sol";
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
    function requestAllocation(uint256, uint256, address) external payable returns (uint64) {
        revert DirectStakeMisused();
    }

    /// @inheritdoc IStrategy
    function claimAllocation(uint256[] calldata, address) external pure returns (uint256) {
        revert DirectStakeMisused();
    }

    /// @inheritdoc IStrategy
    function requestExit(
        uint256 requestId_,
        uint256 shares_,
        address user_) external returns (uint64 readyAt) {
        // just manage request & without transfers

        readyAt = 0; // claimable immediately
        _storeExitRequest(
            requestId_,
            user_,
            shares_,
            readyAt
        );

        emit ExitRequested(requestId_, user_, shares_, readyAt);
    }

    /// @inheritdoc IStrategy
    function claimExit(uint256[] calldata ids_, address receiver_) external returns (uint256 amount) {
        require(ids_.length == 1, DontSupportArrays());
        uint256 id = ids_[0];

        StrategyRequest memory r = _loadClaimable(id, StrategyKind.Exit);

        _markClaimed(id);
        amount = r.amount;

        emit ExitClaimed(id, receiver_, amount);
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
