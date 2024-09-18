// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TestERC20
 * Test Standard ERC20 Token, with an Owner and mint function exposed
 */
contract TestERC20 is Ownable, ERC20 {
    uint8 private decimalNum;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _supply,
        uint8 _decimalNum
    ) Ownable(msg.sender) ERC20(_name, _symbol) {
        _mint(msg.sender, _supply);
        decimalNum = _decimalNum;
    }

    function mint(address to_, uint256 amount_) public onlyOwner {
        _mint(to_, amount_);
    }

    function decimals() public view override returns (uint8) {
        return decimalNum;
    }
}
