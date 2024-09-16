// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LibStaking, StakingStorage, UserStakingPoolInfo} from "../libraries/LibStaking.sol";
import {
    LibReserveStrategy, ReserveStrategyStorage, StrategyInfo, UserStrategyInfo
} from "../libraries/LibReserveStrategy.sol";

import {IStakingStrategy} from "../interfaces/IStakingStrategy.sol";

/**
 * @title ReserveStrategyFacet
 * @notice This contract manages liquidity for a single asset in its reserve, generating yield
 * by staking the asset in external protocols like Lido or Rocket Pool.
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract ReserveStrategyFacet is IStakingStrategy {
    using SafeERC20 for IERC20;

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    modifier validateStrategy(uint256 strategyId) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        StrategyInfo memory strategy = r.strategyInfo[strategyId];

        if (strategyId != strategy.strategyId) revert StrategyDoesNotExist();
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @inheritdoc IStakingStrategy
    function allocate(
        uint256 strategyId,
        uint256 poolId,
        uint256 amount
    ) external validateStrategy(strategyId) {
        StakingStorage storage s = LibStaking.diamondStorage();
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();

        UserStakingPoolInfo storage userPoolInfo = s.userInfo[poolId][msg.sender];
        StrategyInfo storage strategy = r.strategyInfo[strategyId];
        UserStrategyInfo storage userStrategyInfo = r.userInfo[strategyId][msg.sender];

        userStrategyInfo.lockedStake += amount;
        userPoolInfo.totalStakeLocked += amount;
        userStrategyInfo.revenueAssetAllocated = amount * 1e18 / wstETHPrice();

        strategy.totalAllocated += amount;

        emit Allocate(strategyId, poolId, amount);
    }

    /// @inheritdoc IStakingStrategy
    function exit(
        uint256 strategyId,
        uint256 poolId,
        uint256 amount
    ) external validateStrategy(strategyId) {
        StakingStorage storage s = LibStaking.diamondStorage();
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();

        UserStakingPoolInfo storage userPoolInfo = s.userInfo[poolId][msg.sender];
        StrategyInfo storage strategy = r.strategyInfo[strategyId];
        UserStrategyInfo storage userStrategyInfo = r.userInfo[strategyId][msg.sender];

        // calculate exit amount based on strategy exit amount and revenue asset allocation
        uint256 exitAmount =
            (amount * 1e18 / userStrategyInfo.lockedStake) *  // exit share
            (userStrategyInfo.revenueAssetAllocated * wstETHPrice() / 1e18) /
            1e18; // remove factor

        // user revenue
        int256 revenue = int256(exitAmount - amount);

        // Effect
        userStrategyInfo.lockedStake -= amount;
        userPoolInfo.totalStakeLocked -= amount;

        strategy.totalAllocated -= amount;

        userPoolInfo.amount += uint256(revenue);

        emit Exit(strategyId, poolId, amount, revenue);
    }

    // TODO ACL
    function supplyRevenueAsset(
        uint256 strategyId,
        uint256 poolId,
        uint256 amount
    ) external validateStrategy(strategyId) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        StrategyInfo storage strategy = r.strategyInfo[strategyId];

        IERC20(strategy.revenueAsset).transferFrom(msg.sender, address(this), amount);

        strategy.totalRevenueAssetInvested += amount;

        emit RevenueAssetSupply(strategyId, poolId, amount);
    }

    // TODO ACL
    function withdrawRevenueAsset(
        uint256 strategyId,
        uint256 poolId,
        uint256 amount
    ) external validateStrategy(strategyId) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        StrategyInfo storage strategy = r.strategyInfo[strategyId];

        IERC20(strategy.revenueAsset).transfer(msg.sender, amount);

        strategy.totalRevenueAssetInvested -= amount;

        emit RevenueAssetWithdraw(strategyId, poolId, amount);
    }

    // TODO ACL
    function init(uint256 poolId) external {
        _createStrtegy(poolId);
    }

    // ========= View ========= //

    function userShare(uint256 strategyId, address user) public view returns (uint256) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();

        UserStrategyInfo storage userStrategyInfo = r.userInfo[strategyId][user];
        StrategyInfo memory strategy = r.strategyInfo[strategyId];

        uint256 userAllocation = userStrategyInfo.lockedStake;

        uint256 totalAllocated = strategy.totalAllocated;

        // use 1e18 as a scaling factor, where 0.1 ETH == 10%
        return userAllocation * 1e18 / totalAllocated;
    }

    function userInfo(
        uint256 strategyId,
        address user
    ) external view returns (UserStrategyInfo  memory) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        return r.userInfo[strategyId][user];
    }

    function strategyInfo(uint256 strategyId) external view returns (StrategyInfo memory) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        return r.strategyInfo[strategyId];
    }

    function generateStrategyId(uint256 poolId, uint256 idx) public pure returns (uint256) {
        return uint256(keccak256(
            abi.encodePacked(
                poolId,
                idx
            )
        ));
    }

    // TODO remove, only a test mockup
    function wstETHPrice() public pure returns (uint256) {
        return 117 * 1e16; // assume that wstETH is ~17% more expensive than eth
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//


    function _createStrtegy(uint256 poolId) internal returns (uint256 strategyId) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();

        // use current count as idx
        uint256 idx = r.poolStrategyCounts[poolId];
        strategyId = generateStrategyId(poolId, idx);

        // increment pool count
        r.poolStrategyCounts[poolId]++;

        // emit StrategyCreate(msg.sender, poolId, idx);
    }
}
