// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IERC20, ERC20, ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// Ownable by Diamond Proxy -> Vault Facet
contract LiquidVaultToken is ERC4626, Ownable {

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//
    constructor(
        address diamond_,
        IERC20 asset_,
        string memory sharesName,
        string memory sharesSymbol
    ) ERC4626(asset_) ERC20(sharesSymbol, sharesName) Ownable(diamond_) {}
}
