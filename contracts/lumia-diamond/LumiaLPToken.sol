// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title LumiaLPToken
 */
contract LumiaLPToken is Ownable, ERC20Burnable {
    address public interchainFactory;

    constructor(
        address interchainFactory_,
        string memory name_,
        string memory symbol_
    ) Ownable(interchainFactory_) ERC20(name_, symbol_) {
        interchainFactory = interchainFactory_;
    }

    function mint(address to_, uint256 amount_) public onlyOwner {
        _mint(to_, amount_);
    }
}
