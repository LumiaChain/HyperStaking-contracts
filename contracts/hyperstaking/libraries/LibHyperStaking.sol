// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Currency} from "../libraries/CurrencyHandler.sol";

import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

/// General Vault details
/// @param enabled Determines whether deposits to the strategy are enabled or disabled
/// @param direct True if the strategy is direct; false if it is active
/// @param strategy Address of the strategy contract
/// @param stakeCurrency Currency used for staking
/// @param revenueAsset ERC-20 yield token used in the vault
struct VaultInfo {
    bool enabled;
    bool direct;
    address strategy;
    Currency stakeCurrency;
    IERC20Metadata revenueAsset;
}

/// DirectStake specific info
struct DirectStakeInfo {
    uint256 totalStake;
}

/// Users' stakes are not held directly in the pool;
/// instead, they are represented by liquid ERC4626 vault shares bridged to the other chain
struct StakeInfo {
    uint256 totalStake;
    uint256 totalAllocation;
    uint256 bridgeSafetyMargin;
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
    /// @notice Info of each vault
    mapping (address strategy => VaultInfo) vaultInfo;

    /// @notice Info about staking into the vaults
    mapping (address strategy => StakeInfo) stakeInfo;

    /// @notice Info of directStake
    mapping (address strategy => DirectStakeInfo) directStakeInfo;

    /// @notice General lockbox data
    LockboxData lockboxData;
}

library LibHyperStaking {
    bytes32 constant internal HYPERSTAKING_STORAGE_POSITION
        = bytes32(uint256(keccak256("hyperstaking-0.1.storage")) - 1);

    // 1e18 as a scaling factor, e.g. for allocation, percent, e.g. 0.1 ETH (1e17) == 10%
    uint256 constant internal ALLOCATION_POINT_PRECISION = 1e18;
    uint256 constant internal PERCENT_PRECISION = 1e18; // represent 100%

    uint256 constant internal MIN_BRIDGE_SAFETY_MARGIN = 2e16; // 2%

    function diamondStorage() internal pure returns (HyperStakingStorage storage s) {
        bytes32 position = HYPERSTAKING_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
