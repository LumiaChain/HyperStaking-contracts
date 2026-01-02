// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

contract MockOracle7726 {
    function getQuote(uint256 baseAmount, address, address) external pure returns (uint256) {
        return baseAmount; // 1:1
    }
}
