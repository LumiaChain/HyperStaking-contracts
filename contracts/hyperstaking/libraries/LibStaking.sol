// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

// TODO stakeToken to abstract Currency (which supports both native and erc20)

/**
 * @notice Info of each user
 * @param amount Token amount the user has provided
 */
struct UserInfo {
    uint256 amount;
}

/**
 * @notice Info of each pool
 * @param native Eth
 * @param stakeToken Address of the token that users stake in this pool
 * @param totalStake
 */
struct PoolInfo { // TODO consider again this struct fields
    uint256 poolId; // do we need it here?
    bool native; // hmm
    address stakeToken; // keccak("native"), currency instead?
    uint256 totalStake;
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct StakingStorage {
    /// @notice Info of each user that stakes tokens
    mapping (uint256 poolId => mapping (address => UserInfo)) userInfo;

    /// @notice Info of each staking pool
    mapping (uint256 poolId => PoolInfo) poolInfo;

    /// @notice Tracks how many pools have been created for each staking token.
    mapping(address stakeToken => uint256) stakeTokenPoolCounts;
}

library LibStaking {
  bytes32 constant internal STAKING_STORAGE_POSITION = keccak256("hyperstaking-staking.storage");

  function diamondStorage() internal pure returns (StakingStorage storage s) {
    bytes32 position = STAKING_STORAGE_POSITION;
    assembly {
      s.slot := position
    }
  }
}
