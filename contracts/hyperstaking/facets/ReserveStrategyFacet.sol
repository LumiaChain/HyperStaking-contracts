// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IStakingStrategy} from "../interfaces/IStakingStrategy.sol";

import {LibStaking, StakingStorage, UserPoolInfo} from "../libraries/LibStaking.sol";
import {
    LibReserveStrategy, ReserveStrategyStorage, UserStrategyInfo, StrategyInfo, RevenueAsset
} from "../libraries/LibReserveStrategy.sol";

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

        require(strategyId == strategy.strategyId, StrategyDoesNotExist());
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // TODO remove, only for testing purposes
    function init(uint256 poolId, address revenueAsset, uint256 testAssetPrice) external {
        _createStrtegy(poolId, RevenueAsset({
            asset: revenueAsset,
            reserve: 0,
            price: testAssetPrice
        }));
    }

    /// @inheritdoc IStakingStrategy
    function allocate(
        uint256 strategyId,
        address user,
        uint256 amount
    ) external validateStrategy(strategyId) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        StakingStorage storage s = LibStaking.diamondStorage();

        StrategyInfo storage strategy = r.strategyInfo[strategyId];
        RevenueAsset storage asset = r.revenueAssetInfo[strategyId];
        UserPoolInfo storage userPool = s.userInfo[strategy.poolId][user];
        UserStrategyInfo storage userStrategy = r.userInfo[strategyId][user];

        userStrategy.lockedStake += amount;
        userPool.totalStakeLocked += amount; // hmm
        userStrategy.revenueAssetAllocated = amount * 1e18 / asset.price;

        strategy.totalAllocated += amount;

        emit Allocate(strategyId, strategy.poolId, user, amount);
    }

    /// @inheritdoc IStakingStrategy
    function exit(
        uint256 strategyId,
        address user,
        uint256 amount
    ) external returns (uint256 exitAmount) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        StakingStorage storage s = LibStaking.diamondStorage();

        StrategyInfo storage strategy = r.strategyInfo[strategyId];
        RevenueAsset storage asset = r.revenueAssetInfo[strategyId];
        UserPoolInfo storage userPool = s.userInfo[strategy.poolId][user];
        UserStrategyInfo storage userStrategy = r.userInfo[strategyId][user];

        exitAmount = calcUserExitAmount(strategyId, user, amount);

        // user revenue
        int256 revenue = int256(exitAmount) - int256(amount);

        userStrategy.lockedStake -= amount;
        userPool.totalStakeLocked -= amount; // TODO handle userPool in staking
        userStrategy.revenueAssetAllocated -= amount * 1e18 / asset.price;

        strategy.totalAllocated -= amount;

        if (revenue > 0)
            userPool.amount += uint256(revenue);
        else
            userPool.amount -= uint256(-revenue);

        // TODO ensure proper handling of revenueAssetAllocated once actual protocols are integrated

        emit Exit(strategyId, strategy.poolId, user, amount, revenue);

        return exitAmount;
    }

    // TODO ACL
    /// @inheritdoc IStakingStrategy
    function supplyRevenueAsset(
        uint256 strategyId,
        uint256 amount
    ) external validateStrategy(strategyId) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        RevenueAsset storage asset = r.revenueAssetInfo[strategyId];

        IERC20(asset.asset).transferFrom(msg.sender, address(this), amount);

        asset.reserve += amount;

        emit RevenueAssetSupply(msg.sender, strategyId, asset.asset, amount);
    }

    // TODO ACL
    /// @inheritdoc IStakingStrategy
    function withdrawRevenueAsset(
        uint256 strategyId,
        uint256 amount
    ) external {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        RevenueAsset storage asset = r.revenueAssetInfo[strategyId];

        IERC20(asset.asset).transfer(msg.sender, amount);

        asset.reserve -= amount;

        emit RevenueAssetWithdraw(msg.sender, strategyId, asset.asset, amount);
    }

    // ========= View ========= //

    /// @inheritdoc IStakingStrategy
    function userStrategyInfo(
        uint256 strategyId,
        address user
    ) external view returns (UserStrategyInfo  memory) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        return r.userInfo[strategyId][user];
    }

    /// @inheritdoc IStakingStrategy
    function strategyInfo(uint256 strategyId) external view returns (StrategyInfo memory) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        return r.strategyInfo[strategyId];
    }

    /// @inheritdoc IStakingStrategy
    function revenueAssetInfo(uint256 strategyId) external view returns (RevenueAsset memory) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        return r.revenueAssetInfo[strategyId];
    }

    /// @inheritdoc IStakingStrategy
    function userStrategyShare(uint256 strategyId, address user) public view returns (uint256) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();

        UserStrategyInfo storage userStrategy = r.userInfo[strategyId][user];
        StrategyInfo memory strategy = r.strategyInfo[strategyId];

        uint256 userAllocation = userStrategy.lockedStake;

        uint256 totalAllocated = strategy.totalAllocated;

        return userAllocation * LibStaking.PRECISSION_FACTOR / totalAllocated;
    }

    /// @inheritdoc IStakingStrategy
    function calcUserExitAmount(
        uint256 strategyId,
        address user,
        uint256 amount
    ) public view returns (uint256) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();

        UserStrategyInfo storage userStrategy = r.userInfo[strategyId][user];
        RevenueAsset storage asset = r.revenueAssetInfo[strategyId];

        // share part of the total available for user to exit
        uint256 exitPart = (amount * LibStaking.PRECISSION_FACTOR / userStrategy.lockedStake);

        // The total amount of ETH if the entire reserve were converted back to ETH
        uint256 totalEthEquivalent =
            userStrategy.revenueAssetAllocated * asset.price / LibStaking.PRECISSION_FACTOR;

        return
            exitPart * userStrategyShare(strategyId, user) / LibStaking.PRECISSION_FACTOR
            * totalEthEquivalent / 1e18; // TODO use token decimals
    }

    // TODO remove, only a test mockup
    function revenueAssetPrice(uint256 strategyId) public view returns (uint256) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();
        return r.revenueAssetInfo[strategyId].price;

        // TODO move to tests:
        // return 117 * 1e16; // assume that wstETH is ~17% more expensive than eth
    }


    /// @inheritdoc IStakingStrategy
    function generateStrategyId(uint256 poolId, uint256 idx) public pure returns (uint256) {
        return uint256(keccak256(
            abi.encodePacked(
                poolId,
                idx
            )
        ));
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//


    function _createStrtegy(uint256 poolId, RevenueAsset memory revenueAsset) internal returns (uint256 strategyId) {
        ReserveStrategyStorage storage r = LibReserveStrategy.diamondStorage();

        // use current count as idx for Id generation
        uint256 idx = r.poolStrategyCounts[poolId];
        strategyId = generateStrategyId(poolId, idx);

        // increment pool count
        r.poolStrategyCounts[poolId]++;

        // create a new StrategyInfo and store it in storage
        r.strategyInfo[strategyId] = StrategyInfo({
            strategyId: strategyId,
            poolId: poolId,
            totalAllocated: 0
        });

        // save RevenueAsset for this strategy
        r.revenueAssetInfo[strategyId] = revenueAsset;

        emit StrategyCreate(msg.sender, poolId, idx, strategyId);
    }
}
