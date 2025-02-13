// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../interfaces/IStrategy.sol";
import {AbstractStrategy} from "./AbstractStrategy.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";

/**
 * @title ReserveStrategy
 * @notice This contract generate yield by managing liquidity of a single asset.
 *
 * @dev Contract used mainly in tests
 */
contract ReserveStrategy is AbstractStrategy {
    using CurrencyHandler for Currency;
    using SafeERC20 for IERC20;

    uint256 constant internal PRECISSION_FACTOR = 1e18;

    /// Currency used as stake receiving during allocation
    Currency public stake;

    /// Token used as revenue asset sent in exchange for the stake
    address public revenueAsset;

    /// Price of the asset
    uint256 public assetPrice;

    /// Price of the asset
    uint256 public assetReserve;

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event RevenueAssetSupply(
        address indexed from,
        address indexed asset,
        uint256 amount
    );

    event RevenueAssetWithdraw(
        address indexed to,
        address indexed asset,
        uint256 amount
    );

    event AssetPriceSet(
        address indexed from,
        address indexed asset,
        uint256 newAssetPrice
    );

    event Received(
        address indexed from,
        uint256 value
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error BadStakeDecimals();
    error BadAssetDecimals();

    error BadAllocationValue();
    error FailedExitCall();

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    // @param assetPrice_ should be provided with 18 decimal precision
    constructor(
        address diamond_,
        Currency memory stake_,
        IERC20Metadata revenueAsset_,
        uint256 assetPrice_
    ) AbstractStrategy(diamond_) {
        stake = stake_;
        revenueAsset = address(revenueAsset_);
        assetPrice = assetPrice_;
        assetReserve = 0;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IStrategy
    function allocate(
        uint256 stakeAmount_,
        address user_
    ) external payable onlyLumiaDiamond returns (uint256 allocation) {
        allocation = previewAllocation(stakeAmount_);
        assetReserve -= allocation;

        stake.transferFrom(DIAMOND, address(this), stakeAmount_);
        IERC20(revenueAsset).safeIncreaseAllowance(DIAMOND, allocation);

        emit Allocate(user_, stakeAmount_, allocation);
    }


    /// @inheritdoc IStrategy
    function exit(
        uint256 assetAllocation_,
        address user_
    ) external onlyLumiaDiamond returns (uint256 exitAmount) {
        exitAmount = previewExit(assetAllocation_);
        assetReserve += exitAmount;

        IERC20(revenueAsset).transferFrom(DIAMOND, address(this), assetAllocation_);
        stake.transfer(DIAMOND, exitAmount);

        emit Exit(user_, assetAllocation_, exitAmount);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // ========= View ========= //

    /// @inheritdoc IStrategy
    function stakeCurrency() external view returns(Currency memory) {
        return stake;
    }

    /// Return current stake to asset conversion (amount * price)
    function previewAllocation(uint256 stakeAmount_) public view returns (uint256) {
        return stakeAmount_ * PRECISSION_FACTOR / assetPrice;
    }

    /// Return current asset to stake conversion (amount / price)
    function previewExit(uint256 assetAllocation_) public view returns (uint256) {
        return assetAllocation_ * assetPrice / PRECISSION_FACTOR;
    }

    // ========= Admin ========= //

    function supplyRevenueAsset(uint256 amount_) external onlyStrategyManager {
        assetReserve += amount_;

        IERC20(revenueAsset).safeTransferFrom(msg.sender, address(this), amount_);

        emit RevenueAssetSupply(msg.sender, revenueAsset, amount_);
    }

    function withdrawRevenueAsset(uint256 amount_) external onlyStrategyManager {
        assetReserve -= amount_;

        IERC20(revenueAsset).transfer(msg.sender, amount_);

        emit RevenueAssetWithdraw(msg.sender, revenueAsset, amount_);
    }

    function setAssetPrice(uint256 assetPrice_) external onlyStrategyManager {
        assetPrice = assetPrice_;

        emit AssetPriceSet(msg.sender, revenueAsset, assetPrice_);
    }
}
