// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title LumiaAssetToken
 */
contract LumiaAssetToken is Ownable, ERC20Burnable {
    uint8 private immutable DECIMALS;

    address public lumiaDiamond;

    constructor(
        address lumiaDiamond_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) Ownable(lumiaDiamond_) ERC20(name_, symbol_) {
        DECIMALS = decimals_;
        lumiaDiamond = lumiaDiamond_;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Owner ========= //

    function mint(address to_, uint256 amount_) public onlyOwner {
        _mint(to_, amount_);
    }

    // ========= View ========= //

    /// override (default 18 dec)
    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }
}
