// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20, IERC4626} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

/**
 * @notice Info of each user
 * @param amount Token amount the user has provided
 */
struct UserVaultInfo {
    uint256 stakeLocked;
    uint256 allocationPoint; // average asset price - maturity
}

struct VaultTier1 {
    uint256 assetAllocation;
    uint256 totalStakeLocked; // all users in this tier
}

// Users at Tier2 don't have stake stored in the pool anymore,
// as it is represented by ERC4626 vault token, liquid shares
struct VaultTier2 {
    IERC4626 vaultToken;
}

struct VaultInfo {
    uint256 poolId;
    address strategy;
    IERC20 asset;
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct StrategyVaultStorage {
    /// @notice Info of each user that stakes using vault
    mapping (address strategy => mapping (address user => UserVaultInfo)) userInfo;

    /// @notice Info of each vault
    mapping (address strategy => VaultInfo) vaultInfo;

    /// @notice Info of vaults tier1
    mapping (address strategy => VaultTier1) vaultTier1Info;

    /// @notice Info of vaults tier2
    mapping (address strategy => VaultTier2) vaultTier2Info;
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
