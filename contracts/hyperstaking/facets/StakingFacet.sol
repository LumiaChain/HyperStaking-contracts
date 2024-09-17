// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

// import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20Metadata.sol";
// import {SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20.sol";

import {IStakingFacet} from "../interfaces/IStakingFacet.sol";
import {IStakingStrategy} from "../interfaces/IStakingStrategy.sol";

import {
    LibStaking, StakingStorage, UserPoolInfo, StakingPoolInfo
} from "../libraries/LibStaking.sol";

/**
 * @title StakingFacet
 * @notice This contract handles the core staking logic.
 * It allows users to deposit and withdraw tokens from staking pools. The contract supports
 * multiple staking pools for the same token, with each pool having a unique ID.
 * Rewards are distributed based on the user's share in the pool.
 *
 * @dev This contract is a facet of Diamond Proxy.
 */
contract StakingFacet is IStakingFacet {
    // using SafeERC20 for IERC20;

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    modifier validatePool(uint256 poolId) {
        StakingStorage storage s = LibStaking.diamondStorage();
        StakingPoolInfo memory pool = s.poolInfo[poolId];

        if (poolId != s.poolInfo[poolId].poolId) revert PoolDoesNotExist();
        _;
    }

    //============================================================================================//
    //                                     TEST INIT                                              //
    //============================================================================================//

    /// @dev REMOVE THIS FUNCTION, only for testing
    function init() public {
        StakingStorage storage s = LibStaking.diamondStorage();

        address stakeToken = nativeTokenAddress();
        uint256 poolId = _createStakingPool(stakeToken);

        // save test pool in the storage
        s.poolInfo[poolId] = StakingPoolInfo({
            poolId: poolId,
            native: true,
            stakeToken: stakeToken,
            totalStake: 0
        });
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /**
     * @notice Main deposit function
     */
    function stakeDeposit(
        uint256 poolId,
        uint256 strategyId,
        uint256 amount,
        address to
    ) public payable validatePool(poolId) {
        StakingStorage storage s = LibStaking.diamondStorage();

        StakingPoolInfo storage pool = s.poolInfo[poolId];
        UserPoolInfo storage userPool = s.userInfo[poolId][to];

        if (pool.native) {
            if (msg.value != amount) revert DepositBadValue();
        } else {
            revert Unsupported();
        }

        pool.totalStake += amount;
        userPool.amount += amount;

        IStakingStrategy(address(this)).allocate(strategyId, amount);

        emit StakeDeposit(msg.sender, to, poolId, strategyId, amount);
    }

    /**
     * @notice Main withdraw function
     */
    function stakeWithdraw(
        uint256 poolId,
        uint256 strategyId,
        uint256 amount,
        address to
    ) public validatePool(poolId) returns (uint256 withdrawAmount) {
        StakingStorage storage s = LibStaking.diamondStorage();

        StakingPoolInfo storage pool = s.poolInfo[poolId];
        UserPoolInfo storage userPool = s.userInfo[poolId][msg.sender];

        withdrawAmount = IStakingStrategy(address(this)).exit(strategyId, amount);

        if (pool.native) {
            (bool success, ) = to.call{value: withdrawAmount}("");
            if (!success) revert WithdrawFailedCall();
        } else {
            revert Unsupported();
        }

        pool.totalStake -= withdrawAmount;
        userPool.amount -= withdrawAmount;

        emit StakeWithdraw(msg.sender, to, poolId, strategyId, amount, withdrawAmount);
    }

    // ========= View ========= //

    function userPoolInfo(
        uint256 poolId,
        address user
    ) external view returns (UserPoolInfo memory) {
        StakingStorage storage s = LibStaking.diamondStorage();
        return s.userInfo[poolId][user];
    }

    function poolInfo(uint256 poolId) external view returns (StakingPoolInfo memory) {
        StakingStorage storage s = LibStaking.diamondStorage();
        return s.poolInfo[poolId];
    }

    function userPoolShare(uint256 poolId, address user) public view returns (uint256) {
        StakingStorage storage s = LibStaking.diamondStorage();

        StakingPoolInfo storage pool = s.poolInfo[poolId];
        UserPoolInfo storage userPool = s.userInfo[poolId][user];

        return userPool.amount * 1e18 / pool.totalStake;
    }

    // TODO replace with const or Currency
    function nativeTokenAddress() public pure returns (address) {
        return address(uint160(uint256(keccak256("native-eth"))));
    }

    function generatePoolId(address stakeToken, uint96 idx) public pure returns (uint256) {
        return uint256(keccak256(
            abi.encodePacked(
                stakeToken,
                idx
            )
        ));
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    function _createStakingPool(address stakeToken) internal returns (uint256 poolId) {
        StakingStorage storage s = LibStaking.diamondStorage();

        // use current count as idx
        uint96 idx = s.stakeTokenPoolCounts[stakeToken];
        poolId = generatePoolId(stakeToken, idx);

        // increment pool count
        s.stakeTokenPoolCounts[stakeToken]++;

        emit StakingPoolCreate(msg.sender, stakeToken, idx, poolId);
    }
}
