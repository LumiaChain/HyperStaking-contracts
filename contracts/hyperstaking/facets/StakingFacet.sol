// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStaking} from "../interfaces/IStaking.sol";
import {ITier1Vault} from "../interfaces/ITier1Vault.sol";
import {ITier2Vault} from "../interfaces/ITier2Vault.sol";
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

    /// @notice Main Tier1 deposit function
    /// @inheritdoc IStaking
    function stakeDeposit(uint256 poolId, address strategy, uint256 stake, address to)
        external
        payable
        nonReentrant
        whenNotPaused
        validate(poolId, strategy)
    {
        StakingStorage storage s = LibStaking.diamondStorage();

        StakingPoolInfo storage pool = s.poolInfo[poolId];
        UserPoolInfo storage userPool = s.userInfo[poolId][to];

        pool.currency.transferFrom(
            msg.sender,
            address(this),
            stake
        );

        pool.totalStake += stake;
        userPool.staked += stake;

        // will lock user stake
        ITier1Vault(address(this)).joinTier1(strategy, to, stake);

        emit StakeDeposit(msg.sender, to, poolId, strategy, stake, 1);
    }

    /// @notice Tier1 withdraw function
    /// @inheritdoc IStaking
    function stakeWithdraw(uint256 poolId, address strategy, uint256 stake, address to)
        external
        nonReentrant
        whenNotPaused
        validate(poolId, strategy)
        returns (uint256 withdrawAmount)
    {
        StakingStorage storage s = LibStaking.diamondStorage();

        StakingPoolInfo storage pool = s.poolInfo[poolId];
        UserPoolInfo storage userPool = s.userInfo[poolId][msg.sender];

        withdrawAmount = ITier1Vault(address(this)).leaveTier1(strategy, msg.sender, stake);

        // stake should be unlocked at this point
        pool.totalStake -= stake;
        userPool.staked -= stake;

        pool.currency.transfer(
            to,
            withdrawAmount
        );

        emit StakeWithdraw(msg.sender, to, poolId, strategy, stake, withdrawAmount);
    }

    /* ========== Tier 2  ========== */

    /// @notice Tier2 deposit function
    /// @inheritdoc IStaking
    function stakeDepositTier2(uint256 poolId, address strategy, uint256 stake, address to)
        external
        payable
        nonReentrant
        whenNotPaused
        validate(poolId, strategy)
    {
        StakingStorage storage s = LibStaking.diamondStorage();
        StakingPoolInfo storage pool = s.poolInfo[poolId];

        pool.currency.transferFrom(
            msg.sender,
            address(this),
            stake
        );

        // will lock user stake
        ITier2Vault(address(this)).joinTier2(strategy, to, stake);

        emit StakeDeposit(msg.sender, to, poolId, strategy, stake, 2);
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
