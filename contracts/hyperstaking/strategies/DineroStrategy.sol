// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import {StrategyKind, StrategyRequest, IStrategy} from "../interfaces/IStrategy.sol";
import {AbstractStrategy} from "./AbstractStrategy.sol";

import {PirexEth} from "../../external/pirex/PirexEth.sol";
import {AutoPxEth} from "../../external/pirex/AutoPxEth.sol";
import {DataTypes} from "../../external/pirex/libraries/DataTypes.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Currency} from "../../shared/libraries/CurrencyHandler.sol";

/**
 * @title DineroStrategy
 * @notice This contract manages liquidity staking the base (ETH) asset in Pirex protocol
 */
contract DineroStrategy is AbstractStrategy {
    using SafeERC20 for IERC20;

    /// PxEth (ERC20) contract address
    address public PX_ETH;

    /// PirexEth contract address
    address public PIREX_ETH;

    /// AutoPxEth (ERC4626) contract address
    address public AUTO_PX_ETH;

    /// Storage gap for upgradeability. Must remain the last state variable
    uint256[50] private __gap;

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event PirexDepositCompound(
        address indexed receiver,
        uint256 ethDeposited,
        uint256 postFeeAmount,
        uint256 feeAmount,
        uint256 apxEthReceived
    );

    event PirexInstantEthRedeem(
        address indexed receiver,
        uint256 shares, // apxETH
        uint256 pxEthReceived,
        uint256 ethReceived,
        uint256 feeAmount
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error BadAllocationValue();

    //============================================================================================//
    //                                        Initialize                                          //
    //============================================================================================//

    function initialize (
        address diamond_,
        address pxEth_,
        address pirexEth_,
        address autoPxEth_
    ) public initializer {
        __AbstractStrategy_init(diamond_);

        require(pxEth_ != address(0), ZeroAddress());
        require(pirexEth_ != address(0), ZeroAddress());
        require(autoPxEth_ != address(0), ZeroAddress());

        PX_ETH = pxEth_;
        PIREX_ETH = pirexEth_;
        AUTO_PX_ETH = autoPxEth_;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Diamond ========= //

    /// @inheritdoc IStrategy
    function requestAllocation(
        uint256 requestId_,
        uint256 amount_,
        address user_
    ) external payable onlyLumiaDiamond returns (uint64 readyAt) {
        require(amount_ == msg.value, BadAllocationValue());

        readyAt = previewAllocationReadyAt(amount_);
        _storeAllocationRequest(
            requestId_,
            user_,
            amount_,
            readyAt
        );

        emit AllocationRequested(requestId_, user_, amount_, readyAt);
    }

    /// @inheritdoc IStrategy
    function claimAllocation(
        uint256[] calldata ids_, address receiver_
    ) external onlyLumiaDiamond returns (uint256 allocation) {
        require(ids_.length == 1, DontSupportArrays());
        uint256 id = ids_[0];

        StrategyRequest memory r = _loadClaimable(id, StrategyKind.Allocation);
        _markClaimed(id);

        // mint apx for Diamond
        allocation = _depositCompound(receiver_, r.amount);

        emit AllocationClaimed(id, receiver_, allocation);
    }

    /// @inheritdoc IStrategy
    function requestExit(
        uint256 requestId_,
        uint256 shares_,
        address user_
    ) external onlyLumiaDiamond returns (uint64 readyAt) {
        IERC20(AUTO_PX_ETH).safeTransferFrom(DIAMOND, address(this), shares_);

        readyAt = previewExitReadyAt(shares_);
        _storeExitRequest(
            requestId_,
            user_,
            shares_,
            readyAt
        );

        emit ExitRequested(requestId_, user_, shares_, readyAt);
    }

    /// @inheritdoc IStrategy
    function claimExit(
        uint256[] calldata ids_, address receiver_
    ) external onlyLumiaDiamond returns (uint256 exitAmount) {
        require(ids_.length == 1, DontSupportArrays());
        uint256 id = ids_[0];

        StrategyRequest memory r = _loadClaimable(id, StrategyKind.Exit);
        _markClaimed(id);

        // transfer stake amount back to the Diamond
        exitAmount = _redeem(r.amount, receiver_);

        emit ExitClaimed(id, receiver_, exitAmount);
    }

    // ========= View ========= //

    /// @inheritdoc IStrategy
    function stakeCurrency() external pure returns(Currency memory) {
        return Currency({
            token: address(0)
        });
    }

    /// @inheritdoc IStrategy
    function revenueAsset() external view returns(address) {
        return AUTO_PX_ETH;
    }

    /// @inheritdoc IStrategy
    function previewAllocationReadyAt(uint256) public pure returns (uint64 readyAt) {
        readyAt = 0; // claimable immediately -> sync deposit flow
    }

    /// @inheritdoc IStrategy
    function previewExitReadyAt(uint256) public pure returns (uint64 readyAt) {
        readyAt = 0; // claimable immediately -> sync redeem flow
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @dev Deposits ETH into PirexETH with compounding, computes expected apxETH using the pre-deposit ratio
    function _depositCompound(address receiver_, uint256 value) internal returns (uint256 apxEthReceived) {
        require(receiver_ != address(0), ZeroAddress());
        require(value > 0, ZeroAmount());

        // Retrieve this value before making the compound deposit, as it will alter the vault ratio
        apxEthReceived = _convertEthToApxEth(value);

        bool compound = true;
        (uint256 postFeeAmount, uint256 feeAmount) = PirexEth(PIREX_ETH).deposit{
            value: value
        }(
            receiver_,
            compound
        );

        emit PirexDepositCompound(receiver_, value, postFeeAmount, feeAmount, apxEthReceived);
    }

    // `shares_` is the apxETH amount to redeem
    // Flow: apxETH -> pxETH -> ETH (instant redeem via PirexETH)
    function _redeem(uint256 shares_, address receiver_) internal returns (uint256 ethReceived) {
        require(receiver_ != address(0), ZeroAddress());
        require(shares_ > 0, ZeroAmount());

        // apxEth -> pxEth
        uint256 pxEthReceived = AutoPxEth(AUTO_PX_ETH).redeem(shares_, address(this), address(this));

        // pxEth -> Eth
        IERC20(PX_ETH).safeIncreaseAllowance(PIREX_ETH, pxEthReceived);
        uint256 feeAmount;
        (ethReceived, feeAmount) = PirexEth(PIREX_ETH).instantRedeemWithPxEth(
            pxEthReceived,
            receiver_
        );

        emit PirexInstantEthRedeem(receiver_, shares_, pxEthReceived, ethReceived, feeAmount);
    }

    // ========= View ========= //

    /// Return current eth to apxEth ratio (price)
    function _convertEthToApxEth(uint256 amount_) internal view returns (uint256) {
        (uint256 postFeeAmount,) = _computeAssetAmounts(
            DataTypes.Fees.Deposit,
            amount_
        );

        return AutoPxEth(AUTO_PX_ETH).previewDeposit(postFeeAmount);
    }

    /// Return current asset to stake ratio (price)
    function _convertApxEthToEth(uint256 amount_) internal view returns (uint256) {
        uint256 pxEthAmount = AutoPxEth(AUTO_PX_ETH).previewRedeem(amount_);

        (uint256 postFeeAmount,) = _computeAssetAmounts(
            DataTypes.Fees.InstantRedemption,
            pxEthAmount
        );

        return postFeeAmount;
    }

    /**
     * @notice This function calculates the Pirex post-fee asset amount and fee amount based on the
               specified fee type and total assets
     * @dev Source:
     *      https://github.com/dinero-protocol/pirex-eth-contracts/blob/master/src/PirexEth.sol#L545
     *
     * @param f_ representing the fee type
     * @param amount_ Total ETH or pxETH asset amount
     * @return postFeeAmount Post-fee asset amount (for mint/burn/claim/etc.)
     * @return feeAmount Fee amount
     */
    function _computeAssetAmounts(
        DataTypes.Fees f_,
        uint256 amount_
    ) internal view returns (uint256 postFeeAmount, uint256 feeAmount) {
        uint256 denominator = 1_000_000;
        uint32 fee = PirexEth(PIREX_ETH).fees(f_);

        feeAmount = (amount_ * fee) / denominator;
        postFeeAmount = amount_ - feeAmount;
    }

    /// Return current stake to asset ratio (eth/apxEth price)
    function _previewAllocationRaw(uint256 stake_) internal view override returns (uint256) {
        return _convertEthToApxEth(stake_);
    }

    /// Return current asset to stake ratio (apxEth/eth price)
    function _previewExitRaw(uint256 allocation_) internal view override returns (uint256) {
        return _convertApxEthToEth(allocation_);
    }
}
