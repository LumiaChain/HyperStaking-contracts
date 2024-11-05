// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {Currency} from "../libraries/CurrencyHandler.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

/**
 * @notice Info of each user
 * @param amount Token amount the user has provided
 * @param stakeLocked The total amount of tokens locked in vaults across all strategies
 */
struct UserPoolInfo {
    uint256 staked;
    uint256 stakeLocked;
}

/**
 * @notice Info of each pool
 * @param currency The currency being staked in this pool
 * @param totalStake
 */
struct StakingPoolInfo {
    uint256 poolId; // used for validation
    Currency currency;
    uint256 totalStake;
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct StakingStorage {
    /// @notice Info of each user that stakes tokens
    mapping (uint256 poolId => mapping (address => UserPoolInfo)) userInfo;

    /// @notice Info of each staking pool
    mapping (uint256 poolId => StakingPoolInfo) poolInfo;

    /// @notice Tracks how many pools have been created for each staking token.
    mapping(address stakeToken => uint96) stakeTokenPoolCount;
}

library LibStaking {
    bytes32 constant internal STAKING_STORAGE_POSITION = keccak256("hyperstaking-staking.storage");

    // 1e18 as a scaling factor, e.g. for shares, where 0.1 ETH == 10%
    uint256 constant internal TOKEN_PRECISION_FACTOR = 1e18;

    function diamondStorage() internal pure returns (StakingStorage storage s) {
        bytes32 position = STAKING_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
