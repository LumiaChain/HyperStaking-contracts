// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20, ERC20, ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract TestERC4626 is ERC4626 {
    constructor(
        address asset
    ) ERC4626(IERC20(asset)) ERC20(
        string(abi.encodePacked("TestERC4626 shares for", IERC20Metadata(asset).name())),
        string(abi.encodePacked("T4626_", IERC20Metadata(asset).symbol()))
    ) { }
}
