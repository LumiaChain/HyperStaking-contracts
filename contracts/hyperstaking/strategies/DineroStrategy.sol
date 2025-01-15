// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../interfaces/IStrategy.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PirexIntegration} from "./PirexIntegration.sol";

/**
 * @title DineroStrategy
 * @notice This contract manages liquidity staking the base (ETH) asset in Pirex protocol.
 */
contract DineroStrategy is IStrategy, PirexIntegration {
    using SafeERC20 for IERC20;

    /// Lumia Diamond Proxy address
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

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Diamond ========= //

    /// @inheritdoc IStrategy
    function allocate(
        uint256 amount_,
        address user_
    ) external payable onlyLumiaDiamond() returns (uint256 allocation) {
        require(amount_ == msg.value, BadAllocationValue());

        // mint apx and allow Diamond (Vault) to fetch it
        allocation = depositCompound(address(this));
        IERC20(AUTO_PX_ETH).safeIncreaseAllowance(DIAMOND, allocation);

        emit Allocate(user_, amount_, allocation);
    }

    /// @inheritdoc IStrategy
    function exit(
        uint256 shares_,
        address user_
    ) external onlyLumiaDiamond() returns (uint256 exitAmount) {
        IERC20(AUTO_PX_ETH).transferFrom(DIAMOND, address(this), shares_);
        exitAmount = redeem(shares_, DIAMOND); // transfer amount back to the Diamond

        emit Exit(user_, shares_, exitAmount);
    }

    // ========= View ========= //

    /// @inheritdoc IStrategy
    function revenueAsset() external view returns(address) {
        return AUTO_PX_ETH;
    }

    /// Return current stake to asset ratio (eth/apxEth price)
    function previewAllocation(uint256 stakeAmount_) public view returns (uint256) {
        return _convertEthToApxEth(stakeAmount_);
    }

    /// Return current asset to stake ratio (apxEth/eth price)
    function previewExit(uint256 assetAllocation_) public view returns (uint256) {
        return _convertApxEthToEth(assetAllocation_);
    }
}
