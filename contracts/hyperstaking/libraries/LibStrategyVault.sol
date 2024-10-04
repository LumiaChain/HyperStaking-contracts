// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

struct UserVaultInfo {
    uint256 stakeLocked;
}

struct VaultInfo {
    uint256 poolId;
    address strategy;
    uint256 totalStakeLocked; // all users
}

struct VaultAsset {
    address token;
    uint256 totalShares;
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct StrategyVaultStorage {
    /// @notice Info of each user that stakes using vault
    mapping (address strategy => mapping (address user => UserVaultInfo)) userInfo;

    /// @notice Info of each vault
    mapping (address strategy => VaultInfo) vaultInfo;

    /// @notice Info of revenue asset for each strategy
    mapping (address strategy => VaultAsset) vaultAssetInfo;
}

library LibStrategyVault {
    bytes32 constant internal STRATEGY_VAULT_STORAGE_POSITION
        = keccak256("hyperstaking-strategy-vault.storage");

    function diamondStorage() internal pure returns (StrategyVaultStorage storage s) {
        bytes32 position = STRATEGY_VAULT_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
