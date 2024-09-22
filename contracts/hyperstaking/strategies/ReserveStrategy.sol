// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../interfaces/IStrategy.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ReserveStrategy
 * @notice This contract generate yield by managing liquidity of a single asset.
 *
 * @dev Contract used mainly in tests
 */
contract ReserveStrategy is IStrategy {
    using SafeERC20 for IERC20;

    uint256 constant internal PRECISSION_FACTOR = 1e18;

    /// Diamond deployment address
    address public immutable DIAMOND;

    /// Managed address
    address public immutable ASSET;

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

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error NotLumiaDiamond();

    error BadAllocationValue();

    error FailedExitCall();

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
        address asset_,
        uint256 assetPrice_
    ) {
        DIAMOND = diamond_;
        ASSET = asset_;
        assetPrice = assetPrice_;
        assetReserve = 0;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IStrategy
    function allocate(
        uint256 amount_,
        address user_
    ) external payable onlyLumiaDiamond() returns (uint256 allocation) {
        require(amount_ == msg.value, BadAllocationValue());

        allocation = amount_ * PRECISSION_FACTOR / assetPrice;

        emit Allocate(user_, amount_, allocation);
    }


    /// @inheritdoc IStrategy
    function exit(
        uint256 shares_,
        address user_
    ) external onlyLumiaDiamond() returns (uint256 exitAmount) {
        exitAmount = shares_ * assetPrice / PRECISSION_FACTOR;

        IERC20(ASSET).transferFrom(DIAMOND, address(this), shares_);

        // transfer the native coin back
        (bool success, ) = DIAMOND.call{value: exitAmount}("");
        if (!success) revert FailedExitCall();

        emit Exit(user_, shares_, exitAmount);
    }

    // ========= Admin ========= //

    // TODO ACL
    function supplyRevenueAsset(uint256 amount_) external {
        assetReserve += amount_;

        IERC20(ASSET).transferFrom(msg.sender, address(this), amount_);
        IERC20(ASSET).approve(DIAMOND, assetReserve);

        emit RevenueAssetSupply(msg.sender, ASSET, amount_);
    }

    // TODO ACL
    function withdrawRevenueAsset(uint256 amount_) external {
        assetReserve -= amount_;

        IERC20(ASSET).transfer(msg.sender, amount_);

        emit RevenueAssetWithdraw(msg.sender, ASSET, amount_);
    }

    // TODO ACL
    function setAssetPrice(uint256 assetPrice_) external {
        assetPrice = assetPrice_;

        emit AssetPriceSet(msg.sender, ASSET, assetPrice_);
    }
}
