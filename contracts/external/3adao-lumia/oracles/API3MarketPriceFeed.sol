// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../interfaces/IPriceFeed.sol';
import '../utils/constants.sol';

interface IApi3ReaderProxy {
    function read() external view returns (int224 value, uint32 timestamp);
}

contract API3MarketPriceFeed is IPriceFeed, Constants {
    IApi3ReaderProxy public immutable oracle;
    address public immutable override token;
    uint256 public immutable precision;
    uint256 public updateThreshold = 24 hours;

    constructor(address _oracle, address _token) {
        require(
            _oracle != address(0x0),
            'e2637b _oracle must not be address 0x0'
        );
        require(
            _token != address(0x0),
            'e2637b _token must not be address 0x0'
        );
        token = _token;
        oracle = IApi3ReaderProxy(_oracle);
        precision = 1e18; // API3 uses 18 decimals by default
    }

    function price() public view virtual override returns (uint256) {
        (int224 _price, uint32 _timestamp) = oracle.read();
        require(_price > 0, 'e2637b _price must be a positive number');
        require(
            block.timestamp - _timestamp <= updateThreshold,
            'price-outdated'
        );
        return (uint256(int256(_price)) * DECIMAL_PRECISION) / precision;
    }

    function pricePoint() public view override returns (uint256) {
        return price();
    }

    function emitPriceSignal() public override {
        emit PriceUpdate(token, price(), price());
    }
}