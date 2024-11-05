// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStaking} from "../interfaces/IStaking.sol";
import {IStrategyVault} from "../interfaces/IStrategyVault.sol";
import {HyperStakingAcl} from "../HyperStakingAcl.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
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
contract StakingFacet is IStaking, HyperStakingAcl, ReentrancyGuardUpgradeable, PausableUpgradeable {

    using CurrencyHandler for Currency;

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    // validate pool and strategy valut
    modifier validate(uint256 poolId, address strategy) {
        StakingStorage storage s = LibStaking.diamondStorage();
        StrategyVaultStorage storage v = LibStrategyVault.diamondStorage();

        require(poolId == s.poolInfo[poolId].poolId, PoolDoesNotExist());
        require(poolId == v.vaultInfo[strategy].poolId, VaultDoesNotExist());
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /// @notice Main deposit function
    /// @inheritdoc IStaking
    function stakeDeposit(
        uint256 poolId,
        address strategy,
        uint256 amount,
        address to
    ) public payable nonReentrant whenNotPaused validate(poolId, strategy)
    {
        StakingStorage storage s = LibStaking.diamondStorage();

        StakingPoolInfo storage pool = s.poolInfo[poolId];
        UserPoolInfo storage userPool = s.userInfo[poolId][to];

        pool.currency.transferFrom(
            msg.sender,
            address(this),
            amount
        );

        pool.totalStake += amount;
        userPool.staked += amount;

        // will lock user stake
        IStrategyVault(address(this)).deposit(strategy, to, amount);

        emit StakeDeposit(msg.sender, to, poolId, strategy, amount);
    }

    /// @notice Main withdraw function
    /// @inheritdoc IStaking
    function stakeWithdraw(
        uint256 poolId,
        address strategy,
        uint256 amount,
        address to
    ) public nonReentrant whenNotPaused validate(poolId, strategy)
    returns (uint256 withdrawAmount) {
        StakingStorage storage s = LibStaking.diamondStorage();

        StakingPoolInfo storage pool = s.poolInfo[poolId];
        UserPoolInfo storage userPool = s.userInfo[poolId][msg.sender];

        withdrawAmount = IStrategyVault(address(this)).withdraw(strategy, msg.sender, amount);

        // stake should be unlocked at this point
        pool.totalStake -= amount;
        userPool.staked -= amount;

        pool.currency.transfer(
            to,
            withdrawAmount
        );

        emit StakeWithdraw(msg.sender, to, poolId, strategy, amount, withdrawAmount);
    }

    /* ========== ACL  ========== */

    /// @inheritdoc IStaking
    function createStakingPool (
        Currency calldata currency
    ) public onlyStakingManager nonReentrant returns (uint256 poolId) {
        poolId = _createStakingPool(currency);
    }

    /// @inheritdoc IStaking
    function pauseStaking() external onlyStakingManager whenNotPaused {
        _pause();
    }

    /// @inheritdoc IStaking
    function unpauseStaking() external onlyStakingManager whenPaused {
        _unpause();
    }

    // ========= View ========= //

    /// @inheritdoc IStaking
    function userPoolInfo(
        uint256 poolId,
        address user
    ) external view returns (UserPoolInfo memory) {
        StakingStorage storage s = LibStaking.diamondStorage();
        return s.userInfo[poolId][user];
    }

    /// @inheritdoc IStaking
    function stakeTokenPoolCount(
        Currency calldata currency
    ) external view returns (uint96) {
        StakingStorage storage s = LibStaking.diamondStorage();
        return s.stakeTokenPoolCount[currency.token];
    }

    /// @inheritdoc IStaking
    function poolInfo(uint256 poolId) external view returns (StakingPoolInfo memory) {
        StakingStorage storage s = LibStaking.diamondStorage();
        return s.poolInfo[poolId];
    }

    /// @inheritdoc IStaking
    function userPoolShare(uint256 poolId, address user) public view returns (uint256) {
        StakingStorage storage s = LibStaking.diamondStorage();

        StakingPoolInfo storage pool = s.poolInfo[poolId];
        UserPoolInfo storage userPool = s.userInfo[poolId][user];

        return userPool.staked * LibStaking.TOKEN_PRECISION_FACTOR / pool.totalStake;
    }

    /// @inheritdoc IStaking
    function generatePoolId(
        Currency calldata currency,
        uint96 idx
    ) public pure returns (uint256) {
        return uint256(keccak256(
            abi.encodePacked(
                currency.token,
                idx
            )
        ));
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Main logic for initializing a new staking pool
    /// @dev Internal function, called by higher-level functions
    function _createStakingPool(
        Currency calldata currency
    ) internal returns (uint256 poolId) {
        StakingStorage storage s = LibStaking.diamondStorage();

        require(currency.decimals() == 18, BadCurrencyDecimals());

        // use current count as idx
        uint96 idx = s.stakeTokenPoolCount[currency.token];
        poolId = generatePoolId(currency, idx);

        // increment pool count
        s.stakeTokenPoolCount[currency.token]++;

        // save test pool in the storage
        s.poolInfo[poolId] = StakingPoolInfo({
            poolId: poolId,
            currency: currency,
            totalStake: 0
        });

        emit StakingPoolCreate(msg.sender, currency.token, idx, poolId);
    }
}
