// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../interfaces/IStrategy.sol";
import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {IHyperStakingRoles} from "../interfaces/IHyperStakingRoles.sol";

/**
 * @title AbstractStrategy
 */
abstract contract AbstractStrategy is IStrategy {
    using CurrencyHandler for Currency;

    /// Diamond deployment address
    address public immutable DIAMOND;

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event EmergencyWithdraw(
        address indexed sender,
        address indexed currencyToken,
        uint256 amount,
        address indexed to
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error ZeroAddress();
    error ZeroAmount();

    error NotLumiaDiamond();
    error NotStrategyManager();

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    modifier onlyLumiaDiamond() {
        require(msg.sender == DIAMOND, NotLumiaDiamond());
        _;
    }

    modifier onlyStrategyManager() {
        require(
            IHyperStakingRoles(DIAMOND).hasStrategyManagerRole(msg.sender),
            NotStrategyManager()
        );
        _;
    }

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    constructor(
        address diamond_
    ) {
        require(diamond_ != address(0), ZeroAddress());

        DIAMOND = diamond_;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IStrategy
    function isDirectStakeStrategy() external pure virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IStrategy
    function isIntegratedStakeStrategy() external pure virtual returns (bool) {
        return false;
    }

    // ========= StrategyManager ========= //

    /**
     * @notice Emergency withdrawal function for StrategyManagers
     * @dev This should only be used in exceptional cases where tokens are stuck
     *      Strategies should be implemented to ensure funds do not become stranded
     * @param currency_ The currency to withdraw (native or erc20)
     * @param amount_ The amount to withdraw
     * @param to_ The recipient address
     */
    function emergencyWithdrawal(
        Currency memory currency_,
        uint256 amount_,
        address to_
    ) external onlyStrategyManager {
        currency_.transfer(to_, amount_);
        emit EmergencyWithdraw(msg.sender, currency_.token, amount_, to_);
    }
}
