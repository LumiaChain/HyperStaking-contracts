// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC4626} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

/// @notice Info of each user (Tier1)
struct UserTier1Info {
    uint256 stakeLocked;
    uint256 allocationPoint; // average asset price - maturity
}

/// @notice Information for each Tier 2 user
/// @param shares VaultToken shares held by the user
/// @param allocation Allocation corresponding to the user’s shares
/// @param stake Amount of the underlying asset allocation corresponding to the user's shares
struct UserTier2Info {
    uint256 shares;
    uint256 allocation;
    uint256 stake;
}

struct VaultTier1 {
    uint256 assetAllocation;
    uint256 totalStakeLocked; // all users in this tier
    uint256 revenueFee; // 18 dec precision
}

// Users at Tier2 don't have stake stored in the pool anymore,
// as it is represented by ERC4626 vault token - liquid shares
struct VaultTier2 {
    IERC4626 vaultToken;
}

struct VaultInfo {
    uint256 poolId;
    address strategy;
    IERC20Metadata asset;
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct StrategyVaultStorage {
    /// @notice Info of each user that stakes using vault
    mapping (address strategy => mapping (address user => UserTier1Info)) userInfo;

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

    uint256 constant internal ALLOCATION_POINT_PRECISION = 1e18;

    uint256 constant internal PERCENT_PRECISION = 1e18; // represent 100%

    function diamondStorage() internal pure returns (StrategyVaultStorage storage s) {
        bytes32 position = STRATEGY_VAULT_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
