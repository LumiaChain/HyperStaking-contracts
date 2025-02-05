// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC4626} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Currency} from "../libraries/CurrencyHandler.sol";

import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

/// @notice Info of each user (Tier1)
struct UserTier1Info {
    uint256 stake;
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
    uint256 totalStake; // all users stake in this tier
    uint256 revenueFee; // 18 dec precision
}

// Users at Tier2 don't have stake stored in the pool (storage) anymore,
// as it is represented by ERC4626 vault token - liquid shares
struct VaultTier2 {
    IERC4626 vaultToken;
}

/// Main vault details.
/// @param stakeCurrency Currency used for staking
/// @param strategy Address of the strategy contract
/// @param asset ERC-20 token used in the vault
struct VaultInfo {
    Currency stakeCurrency;
    address strategy;
    IERC20Metadata asset;
}

struct HyperlaneMessage {
    address sender;
    bytes data;
}

struct LockboxData {
    IMailbox mailbox; /// Hyperlane Mailbox
    uint32 destination; /// ChainID - route destination
    address lumiaFactory; /// Destinaion contract which will be receiving messages
    HyperlaneMessage lastMessage; /// Information about last mailbox message received
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct HyperStakingStorage {
    /// @notice Info of each user that stakes using vault
    mapping (address strategy => mapping (address user => UserTier1Info)) userInfo;

    /// @notice Info of each vault
    mapping (address strategy => VaultInfo) vaultInfo;

    /// @notice Info of vaults tier1
    mapping (address strategy => VaultTier1) vaultTier1Info;

    /// @notice Info of vaults tier2
    mapping (address strategy => VaultTier2) vaultTier2Info;

    /// @notice General lockbox data
    LockboxData lockboxData;
}

library LibHyperStaking {
    bytes32 constant internal STRATEGY_VAULT_STORAGE_POSITION
        = keccak256("hyperstaking-0.1.storage");

    // 1e18 as a scaling factor, e.g. for allocation, percent, e.g. 0.1 ETH (1e17) == 10%
    uint256 constant internal ALLOCATION_POINT_PRECISION = 1e18;
    uint256 constant internal PERCENT_PRECISION = 1e18; // represent 100%

    function diamondStorage() internal pure returns (HyperStakingStorage storage s) {
        bytes32 position = STRATEGY_VAULT_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
