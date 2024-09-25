// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../interfaces/IStrategy.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PirexIntegration} from "./PirexIntegration.sol";

/**
 * @title DineroStrategy
 * @notice This contract manages liquidity staking the base (ETH) asset in Pirex protocol.
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract DineroStrategy is IStrategy, PirexIntegration {
    using SafeERC20 for IERC20;

    /// Diamond deployment address
    address public immutable DIAMOND;

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error NotLumiaDiamond();

    error BadAllocationValue();

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    modifier onlyLumiaDiamond() {
        require(msg.sender == DIAMOND, NotLumiaDiamond());
        _;
    }

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//
    constructor(
        address diamond_,
        address pxEth_,
        address pirexEth_,
        address autoPxEth_
    ) PirexIntegration(pxEth_, pirexEth_, autoPxEth_) {
        DIAMOND = diamond_;
    }

    /// @inheritdoc IStrategy
    function allocate(
        uint256 amount_,
        address user_
    ) external payable onlyLumiaDiamond() returns (uint256 allocation) {
        require(amount_ == msg.value, BadAllocationValue());

        // mint apx and allow Diamond (Vault) to fetch it
        allocation = super.depositCompound(address(this));
        IERC20(AUTO_PX_ETH).safeIncreaseAllowance(DIAMOND, allocation);

        emit Allocate(user_, amount_, allocation);
    }

    /// @inheritdoc IStrategy
    function exit(
        uint256 shares_,
        address user_
    ) external onlyLumiaDiamond() returns (uint256 exitAmount) {
        IERC20(AUTO_PX_ETH).transferFrom(DIAMOND, address(this), shares_);
        exitAmount = super.redeem(shares_, DIAMOND); // transfer amount back to the Diamond

        emit Exit(user_, shares_, exitAmount);
    }
}
