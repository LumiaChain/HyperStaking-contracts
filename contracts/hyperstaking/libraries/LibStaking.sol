// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

// TODO stakeToken to abstract Currency (which supports both native and erc20)

/**
 * @notice Info of each user
 * @param amount Token amount the user has provided
 * @param locked A mapping of strategy IDs to the amount of tokens locked in those strategies
 * @param totalLocked The total amount of tokens locked across all strategies
 */
struct UserPoolInfo {
    uint256 amount;
    uint256 totalStakeLocked;
}

/**
 * @notice Info of each pool
 * @param native Eth
 * @param stakeToken Address of the token that users stake in this pool
 * @param totalStake
 */
struct StakingPoolInfo { // TODO consider again this struct fields
    uint256 poolId; // used for validation
    bool native; // hmm
    address stakeToken;
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
    mapping(address stakeToken => uint96) stakeTokenPoolCounts;
}

library LibStaking {
  bytes32 constant internal STAKING_STORAGE_POSITION = keccak256("hyperstaking-staking.storage");

  // 1e18 as a scaling factor, e.g. for shares, where 0.1 ETH == 10%
  uint256 constant internal PRECISSION_FACTOR = 1e18;

  function diamondStorage() internal pure returns (StakingStorage storage s) {
    bytes32 position = STAKING_STORAGE_POSITION;
    assembly {
      s.slot := position
    }
  }
}
