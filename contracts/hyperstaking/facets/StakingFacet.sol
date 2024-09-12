// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

// import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20Metadata.sol";
// import {SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20.sol";

import {LibStaking, StakingStorage, UserInfo, PoolInfo} from "../libraries/LibStaking.sol";
import {IStakingFacet} from "../interfaces/IStakingFacet.sol";

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
        PoolInfo memory pool = s.poolInfo[poolId];

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
        s.poolInfo[poolId] = PoolInfo({
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
        uint256 amount,
        address to
    ) public payable validatePool(poolId) {
        StakingStorage storage s = LibStaking.diamondStorage();

        PoolInfo storage pool = s.poolInfo[poolId];
        UserInfo storage user = s.userInfo[poolId][to];

        // Effects
        user.amount += amount;
        pool.totalStake += amount;

        // Interactions
        if (pool.native) {
            if (msg.value != amount) revert DepositBadValue();
        } else {
            revert Unsupported();
        }

        emit StakeDeposit(msg.sender, poolId, amount, to);
    }

    /**
     * @notice Main withdraw function
     */
    function stakeWithdraw(uint256 poolId, uint256 amount, address to) public validatePool(poolId) {
        StakingStorage storage s = LibStaking.diamondStorage();

        PoolInfo storage pool = s.poolInfo[poolId];
        UserInfo storage user = s.userInfo[poolId][msg.sender];

        // Effects
        user.amount -= amount;
        pool.totalStake -= amount;

        // Interactions
        if (pool.native) {
            (bool success, ) = to.call{value: amount}("");
            if (!success) revert WithdrawFailedCall();
        } else {
            revert Unsupported();
        }

        emit StakeWithdraw(msg.sender, poolId, amount, to);
    }

    // ========= View ========= //

    function userInfo(uint256 poolId, address user) external view returns (UserInfo memory) {
        StakingStorage storage s = LibStaking.diamondStorage();
        return s.userInfo[poolId][user];
    }

    function poolInfo(uint256 poolId) external view returns (PoolInfo memory) {
        StakingStorage storage s = LibStaking.diamondStorage();
        return s.poolInfo[poolId];
    }

    // TODO replace with const or Currency
    function nativeTokenAddress() public pure returns (address) {
        return address(uint160(uint256(keccak256("native"))));
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
