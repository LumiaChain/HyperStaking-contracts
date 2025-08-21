// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {StrategyKind, StrategyRequest, IStrategy} from "../hyperstaking/interfaces/IStrategy.sol";
import {AbstractStrategy} from "../hyperstaking/strategies/AbstractStrategy.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency, CurrencyHandler} from "../hyperstaking/libraries/CurrencyHandler.sol";

// WARNING: Mock strategy for testing only. Not for production use.

/**
 * @title MockReserveStrategy
 * @notice This contract generate yield by managing liquidity of a single asset
 *
 * @dev Contract used mainly in tests
 */
contract MockReserveStrategy is AbstractStrategy {
    using CurrencyHandler for Currency;
    using SafeERC20 for IERC20;

    uint256 constant internal PRECISSION_FACTOR = 1e18;

    /// Currency used as stake receiving during allocation
    Currency private stake;

    /// Token used as revenue asset sent in exchange for the stake
    address public revenueAsset;

    /// Price of the asset
    uint256 public assetPrice;

    /// Price of the asset
    uint256 public assetReserve;

    error MissingCollateral();

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

    event StakeAssetWithdraw(
        address indexed to,
        address indexed stakeToken,
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
    function requestAllocation(
        uint256 requestId_,
        uint256 stakeAmount_,
        address user_
    ) external payable onlyLumiaDiamond returns (uint64 readyAt) {
        // fetch stake
        stake.transferFrom(DIAMOND, address(this), stakeAmount_);

        readyAt = 0; // claimable immediately
        _storeAllocationRequest(
            requestId_,
            user_,
            stakeAmount_,
            readyAt
        );

        emit AllocationRequested(requestId_, user_, stakeAmount_, readyAt);
    }

    /// @inheritdoc IStrategy
    function claimAllocation(
        uint256[] calldata ids_, address receiver_
    ) external onlyLumiaDiamond returns (uint256 allocation) {
        require(ids_.length == 1, DontSupportArrays());
        uint256 id = ids_[0];

        StrategyRequest memory r = _loadClaimable(id, StrategyKind.Allocation);
        _markClaimed(id);

        allocation = previewAllocation(r.amount);
        assetReserve -= allocation;

        // transfer allocation
        IERC20(revenueAsset).safeTransfer(receiver_, allocation);

        emit AllocationClaimed(id, receiver_, allocation);
    }

    /// @inheritdoc IStrategy
    function requestExit(
        uint256 requestId_,
        uint256 assetAllocation_,
        address user_
    ) external onlyLumiaDiamond returns (uint64 readyAt) {
        // extra check used for testing reexecute
        require(
            stake.balanceOf(address(this)) >= _previewExitRaw(assetAllocation_),
            MissingCollateral()
        );

        readyAt = 0; // claimable immediately
        _storeExitRequest(
            requestId_,
            user_,
            assetAllocation_,
            readyAt
        );

        // fetch allocation (shares)
        IERC20(revenueAsset).transferFrom(DIAMOND, address(this), assetAllocation_);

        emit ExitRequested(requestId_, user_, assetAllocation_, readyAt);
    }

    /// @inheritdoc IStrategy
    function claimExit(
        uint256[] calldata ids_, address receiver_
    ) external onlyLumiaDiamond returns (uint256 exitAmount) {
        require(ids_.length == 1, DontSupportArrays());
        uint256 id = ids_[0];

        StrategyRequest memory r = _loadClaimable(id, StrategyKind.Exit);
        _markClaimed(id);

        exitAmount = previewExit(r.amount);
        assetReserve += exitAmount;

        // transfer stake
        stake.transfer(receiver_, exitAmount);

        emit ExitClaimed(id, receiver_, exitAmount);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // ========= View ========= //

    /// @inheritdoc IStrategy
    function stakeCurrency() external view returns(Currency memory) {
        return stake;
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

    function withdrawStakeAsset(uint256 amount_) external onlyStrategyManager {
        stake.transfer(msg.sender, amount_);

        emit StakeAssetWithdraw(msg.sender, stake.token, amount_);
    }

    function setAssetPrice(uint256 assetPrice_) external onlyStrategyManager {
        assetPrice = assetPrice_;

        emit AssetPriceSet(msg.sender, revenueAsset, assetPrice_);
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// Return current stake to asset conversion (amount * price)
    function _previewAllocationRaw(uint256 stake_) internal view override returns (uint256) {
        return stake_ * PRECISSION_FACTOR / assetPrice;
    }

    /// Return current asset to stake conversion (amount / price)
    function _previewExitRaw(uint256 allocation_) internal view override returns (uint256) {
        return allocation_ * assetPrice / PRECISSION_FACTOR;
    }
}
