// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {
    MessageType, HyperlaneMailboxMessages
} from "../hyperstaking/libraries/HyperlaneMailboxMessages.sol";

/// @notice Test wrapper for HyperlaneMailboxMessages library
contract TestHyperlaneMessages {
    using HyperlaneMailboxMessages for bytes;

    // ========= Serialize ========= //

    function serializeRouteRegistry(
        address strategy_,
        address rwaAsset_,
        bytes memory metadata_
    ) external pure returns (bytes memory) {
        return HyperlaneMailboxMessages.serializeRouteRegistry(
            strategy_,
            rwaAsset_,
            metadata_
        );
    }

    function serializeStakeInfo(
        address strategy_,
        address sender_,
        uint256 stakeAmount_
    ) external pure returns (bytes memory) {
        return HyperlaneMailboxMessages.serializeStakeInfo(
            strategy_,
            sender_,
            stakeAmount_
        );
    }

    function serializeMigrationInfo(
        address fromStrategy_,
        address toStrategy_,
        uint256 migrationAmount_
    ) external pure returns (bytes memory) {
        return HyperlaneMailboxMessages.serializeMigrationInfo(
            fromStrategy_,
            toStrategy_,
            migrationAmount_
        );
    }

    function serializeStakeRedeem(
        address strategy_,
        address sender_,
        uint256 redeemAmount_
    ) external pure returns (bytes memory) {
        return HyperlaneMailboxMessages.serializeStakeRedeem(
            strategy_,
            sender_,
            redeemAmount_
        );
    }

    // ========= General ========= //

    function messageType(bytes calldata message) external pure returns (MessageType) {
        return message.messageType();
    }

    function strategy(bytes calldata message) external pure returns (address) {
        return message.strategy();
    }

    // ========= RouteRegistry ========= //

    function rwaAsset(bytes calldata message) external pure returns (address) {
        return message.rwaAsset();
    }

    function routeRegistryMetadata(bytes calldata message) external pure returns (bytes calldata) {
        return message.routeRegistryMetadata();
    }

    // ========= MigrationInfo ========= //

    function fromStrategy(bytes calldata message) external pure returns (address) {
        return message.fromStrategy();
    }

    function toStrategy(bytes calldata message) external pure returns (address) {
        return message.toStrategy();
    }

    function migrationAmount(bytes calldata message) external pure returns (uint256) {
        return message.migrationAmount();
    }

    // ========= StakeInfo & StakeRedeem  ========= //

    function sender(bytes calldata message) external pure returns (address) {
        return message.sender();
    }

    // ========= StakeInfo ========= //

    function stakeAmount(bytes calldata message) external pure returns (uint256) {
        return message.stakeAmount();
    }

    // ========= TokenRedeem  ========= //

    function redeemAmount(bytes calldata message) external pure returns (uint256) {
        return message.redeemAmount();
    }
}
