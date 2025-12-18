// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {HyperlaneMailboxMessages} from "./HyperlaneMailboxMessages.sol";
import {HyperlaneReplay} from "../Errors.sol";

/**
 * @notice Application-layer replay protection for Hyperlane message handling
 * @dev Each diamond keeps its own storage on its chain. The library is shared across diamonds for
 *      consistent behavior and auditability, but it does not share state across chains
 */

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct ReplayGuardStorage {
    /// @notice Monotonic nonce for outbound messages
    uint64 nonce;

    /// @notice Processed inbound message keys (idempotency guard)
    /// @dev Key is derived from (origin, sender, messageType, nonce)
    mapping(bytes32 msgKey => bool) processedKeys;
}

//================================================================================================//
//                                           Library                                              //
//================================================================================================//

library LibHyperlaneReplayGuard {
    using HyperlaneMailboxMessages for bytes;

    // -------------------- Constants

    bytes32 constant internal STORAGE_POSITION
        = bytes32(uint256(keccak256("lumia.hyperlane-replay-guard-0.1.storage")) - 1);

    // -------------------- Helpers

    /// @dev Increments global counter and returns the new value
    function newNonce() internal returns (uint64) {
        return ++diamondStorage().nonce;
    }

    /// @notice Marks msgKey as processed and reverts on duplicates
    function requireNotProcessed(bytes32 msgKey) internal {
        ReplayGuardStorage storage s = diamondStorage();
        require(!s.processedKeys[msgKey], HyperlaneReplay(msgKey));
        s.processedKeys[msgKey] = true;
    }

    /// @notice Convenience helper computing the replay key from Hyperlane handler inputs
    /// @dev Assumes `data` includes messageType and nonce
    function requireNotProcessedData(
        uint32 origin,
        bytes32 sender,
        bytes calldata data
    ) internal {
        requireNotProcessed(
            genKey(origin,sender,data)
        );
    }

    /// @notice Returns the nonce that would be used by the next outbound dispatch
    function previewNonce() internal view returns (uint64) {
        return diamondStorage().nonce + 1;
    }

    /// @dev Checks if message was processed
    function isProcessed(bytes32 msgKey) internal view returns (bool) {
        return diamondStorage().processedKeys[msgKey];
    }

    /// @notice Derives a stable replay-protection key for handled message
    function genKey(
        uint32 origin,
        bytes32 sender,
        bytes calldata data // assume data has nonce included
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(origin, sender, data.messageType(), data.nonce()));
    }

    // -------------------- Storage Access

    function diamondStorage() internal pure returns (ReplayGuardStorage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
