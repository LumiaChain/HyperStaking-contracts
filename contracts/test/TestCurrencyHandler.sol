// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Currency, CurrencyHandler} from "../shared/libraries/CurrencyHandler.sol";

contract TestCurrencyHandler {
    using CurrencyHandler for Currency;

    function transferFromNativeToThis(
        address from,
        uint256 amount
    ) external payable {
        Currency memory c = Currency({ token: address(0) });
        c.transferFrom(from, address(this), amount);
    }

    function transferFromNativeTo(
        address from,
        address to,
        uint256 amount
    ) external payable {
        Currency memory c = Currency({ token: address(0) });
        c.transferFrom(from, to, amount);
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
