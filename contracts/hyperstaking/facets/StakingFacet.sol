// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStakingFacet} from "../interfaces/IStakingFacet.sol";
import {IStrategyVault} from "../interfaces/IStrategyVault.sol";

import {
    LibStaking, StakingStorage, UserPoolInfo, StakingPoolInfo
} from "../libraries/LibStaking.sol";

import {LibStrategyVault, StrategyVaultStorage} from "../libraries/LibStrategyVault.sol";

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
    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    // validate pool and strategy valut
    modifier validate(uint256 poolId, address strategy) {
        StakingStorage storage s = LibStaking.diamondStorage();
        StrategyVaultStorage storage r = LibStrategyVault.diamondStorage();

        require(poolId == s.poolInfo[poolId].poolId, PoolDoesNotExist());
        require(poolId == r.vaultInfo[strategy].poolId, VaultDoesNotExist());
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
        address strategy,
        uint256 amount,
        address to
    ) public payable validate(poolId, strategy) {
        StakingStorage storage s = LibStaking.diamondStorage();

        StakingPoolInfo storage pool = s.poolInfo[poolId];
        UserPoolInfo storage userPool = s.userInfo[poolId][to];

        if (pool.native) {
            if (msg.value != amount) revert DepositBadValue();
        } else {
            revert Unsupported();
        }

        pool.totalStake += amount;
        userPool.staked += amount;

        // will lock user stake
        IStrategyVault(address(this)).deposit(strategy, amount, to);

        emit StakeDeposit(msg.sender, to, poolId, strategy, amount);
    }

    /**
     * @notice Main withdraw function
     */
    function stakeWithdraw(
        uint256 poolId,
        address strategy,
        uint256 amount,
        address to
    ) public validate(poolId, strategy) returns (uint256 withdrawAmount) {
        StakingStorage storage s = LibStaking.diamondStorage();

        StakingPoolInfo storage pool = s.poolInfo[poolId];
        UserPoolInfo storage userPool = s.userInfo[poolId][msg.sender];

        withdrawAmount = IStrategyVault(address(this)).withdraw(strategy, amount, msg.sender);

        // stake should be unlocked at this point
        pool.totalStake -= amount;
        userPool.staked -= amount;

        if (pool.native) {
            (bool success, ) = to.call{value: withdrawAmount}("");
            if (!success) revert WithdrawFailedCall();
        } else {
            revert Unsupported();
        }

        emit StakeWithdraw(msg.sender, to, poolId, strategy, amount, withdrawAmount);
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

        return userPool.staked * LibStaking.PRECISSION_FACTOR / pool.totalStake;
    }

    // TODO replace with WETH or abstract Currency
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
