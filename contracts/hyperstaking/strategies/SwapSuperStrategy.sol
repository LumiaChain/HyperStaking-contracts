// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../interfaces/IStrategy.sol";
import {Currency, SuperformStrategy} from "./SuperformStrategy.sol";
import {ICurveIntegration} from "../interfaces/ICurveIntegration.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Curve-Swap Superform Strategy
 * @notice Wraps SuperformStrategy with a pre-swap via Curve Router
 */
contract SwapSuperStrategy is SuperformStrategy {
    using SafeERC20 for IERC20;

    /// The actual token address used in allocation, must be swaped before it can be used with superform
    IERC20 public CURVE_INPUT_TOKEN;

    /// 3Pool, etc.
    address public CURVE_POOL;

    /// Curve integration - (diamond facet)
    ICurveIntegration public curveIntegration;

     /// @dev Maximum slippage in basis points (1 bp = 0.01 %)
    uint256 private slippageBps;

    /// Storage gap for upgradeability. Must remain the last state variable
    uint256[50] private __gap;

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event CurveSwapAllocate(
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        uint256 slippageBps
    );

    event CurveSwapExit(
        address indexed user,
        address indexed receiver,
        uint256 amountIn,
        uint256 amountOut,
        uint256 slippageBps
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error SlippageTooHigh();

    //============================================================================================//
    //                                        Initialize                                          //
    //============================================================================================//

    function initialize (
        address diamond_,
        address curveInputToken_,
        address curvePool_,
        address superVault_,
        address superformInputToken_ // This contract takes different stake/deposit token than superform
    ) public initializer {
        __AbstractStrategy_init(diamond_);
        __SuperformStrategy_init(diamond_, superVault_, superformInputToken_);

        require(curveInputToken_ != address(0), ZeroAddress());
        require(curvePool_ != address(0), ZeroAddress());

        CURVE_INPUT_TOKEN = IERC20(curveInputToken_);
        CURVE_POOL = curvePool_;

        curveIntegration = ICurveIntegration(diamond_);
        slippageBps = 50; // default 0.5% slippage
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
    ) public payable override onlyLumiaDiamond returns (uint64 readyAt) {
        require(amount_ > 0, ZeroAmount());

        // requestAllocation uses already uses Curve integration to store a claim request
        // which later fulfills using the swapped out-amount in Superform Strategy

        // slippage adjusted
        uint256 expected = curveIntegration.quote(
            address(CURVE_INPUT_TOKEN),
            CURVE_POOL,
            address(SUPERFORM_INPUT_TOKEN),
            amount_
        );
        uint256 minDy = (expected * (10_000 - slippageBps)) / 10_000;

        // execute the swap; tokens arrive in sender (diamond)
        uint256 amountOut = curveIntegration.swap(
            address(CURVE_INPUT_TOKEN),
            CURVE_POOL,
            address(SUPERFORM_INPUT_TOKEN),
            amount_,
            minDy,
            msg.sender
        );

        emit CurveSwapAllocate(user_, amount_, amountOut, slippageBps);

        // store request (for superform)
        readyAt = 0; // claimable immediately
        _storeAllocationRequest(
            requestId_,
            user_,
            amountOut,
            readyAt
        );

        emit AllocationRequested(requestId_, user_, amountOut, readyAt);
    }

    /// NOTE: There is no need to override claimAllocation and requestExit

    /// @inheritdoc IStrategy
    function claimExit(
        uint256[] calldata ids_,
        address receiver_
    ) public override onlyLumiaDiamond returns (uint256 exitAmount) {
        // redeem from Superform – tokens land in this contract
        uint256 superformOut = super.claimExit(ids_, address(curveIntegration));

        // slippage-adjusted quote
        uint256 expected = curveIntegration.quote(
            address(SUPERFORM_INPUT_TOKEN),   // tokenIn
            CURVE_POOL,
            address(CURVE_INPUT_TOKEN),       // tokenOut
            superformOut
        );
        uint256 minDx = (expected * (10_000 - slippageBps)) / 10_000;

        // swap back to stake token
        exitAmount = curveIntegration.swap(
            address(SUPERFORM_INPUT_TOKEN),
            CURVE_POOL,
            address(CURVE_INPUT_TOKEN),
            superformOut,
            minDx,
            receiver_
        );

        emit CurveSwapExit(_req[ids_[0]].user, receiver_, superformOut, exitAmount, slippageBps);
    }

    // ========= Admin ========= //

    /// @notice Change the slippage tolerance for allocation and exit
    /// @param bps New limit in basis points (10 000 = 100 %).
    function setSlippage(uint256 bps) external onlyStrategyManager {
        require(bps <= 10_000, SlippageTooHigh());
        slippageBps = bps;
    }

    // ========= View ========= //

    /// @inheritdoc IStrategy
    function stakeCurrency() public view override returns(Currency memory) {
        return Currency({
            token: address(CURVE_INPUT_TOKEN)
        });
    }

    /// @inheritdoc IStrategy
    function revenueAsset() public view override returns(address) {
        return super.revenueAsset();
    }

    /// @return Current slippage setting in basis points
    function slippage() external view returns (uint256) {
        return slippageBps;
    }


    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @dev Converts the incoming stake (CURVE_INPUT_TOKEN) amount to its Curve quote
    ///      (SUPERFORM_INPUT_TOKEN), then feeds that into the parent (Superform Strategy) preview
    function _previewAllocationRaw(uint256 stake_) internal view override returns (uint256 allocation) {
        uint256 superformInput = curveIntegration.quote(
            address(CURVE_INPUT_TOKEN),     // tokenIn
            CURVE_POOL,
            address(SUPERFORM_INPUT_TOKEN), // tokenOut
            stake_
        );
        allocation = super._previewAllocationRaw(superformInput);
    }

    /// @dev Works in reverse: first asks the parent (Superform Strategy) how many SUPERFORM_INPUT_TOKEN
    ///      are returned, then quotes Curve for the final exit amount
    function _previewExitRaw(uint256 allocation_) internal view override returns (uint256 stake) {
        uint256 superformOutput = super._previewExitRaw(allocation_);

        stake = curveIntegration.quote(
            address(SUPERFORM_INPUT_TOKEN), // tokenIn
            CURVE_POOL,
            address(CURVE_INPUT_TOKEN),     // tokenOut
            superformOutput
        );
    }
}
