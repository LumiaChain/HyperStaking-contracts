// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

struct UserStrategyInfo {
    uint256 strategyId; // used for validation
    uint256 poolId;
    uint256 lockedStake;
    uint256 revenueAssetAllocated;
}

struct StrategyInfo {
    uint256 strategyId; // used for validation
    uint256 poolId;
    address stakeToken;
    address revenueAsset;
    uint256 totalAllocated;
    uint256 totalRevenueAssetInvested;
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct ReserveStrategyStorage {
    /// @notice Info of each strategy
    mapping (uint256 strategyId => StrategyInfo) strategyInfo;

    /// @notice Info of each user that stakes tokens
    mapping (uint256 strategyId => mapping (address => UserStrategyInfo)) userInfo;

    /// @notice Tracks how many strategies have been created for each poolId.
    mapping(uint256 poolId => uint256) poolStrategyCounts;
}

library LibReserveStrategy {
  bytes32 constant internal RESERVE_STRATEGY_STORAGE_POSITION
    = keccak256("hyperstaking-reserve-strategy.storage");

  function diamondStorage() internal pure returns (ReserveStrategyStorage storage s) {
    bytes32 position = RESERVE_STRATEGY_STORAGE_POSITION;
    assembly {
      s.slot := position
    }
  }
}
