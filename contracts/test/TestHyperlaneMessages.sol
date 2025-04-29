// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {
    MessageType,
    RouteRegistryData,
    StakeInfoData,
    HyperlaneMailboxMessages
} from "../hyperstaking/libraries/HyperlaneMailboxMessages.sol";

/// @notice Test wrapper for HyperlaneMailboxMessages library
contract TestHyperlaneMessages {
    using HyperlaneMailboxMessages for bytes;

    // ========= Helper ========= //

    function stringToBytes32(
        string memory source
    ) external pure returns (uint8 size, bytes32 result) {
        return HyperlaneMailboxMessages.stringToBytes32(source);
    }

    function stringToBytes64(
        string memory source
    ) external pure returns (uint8 size, bytes32[2] memory result) {
        return HyperlaneMailboxMessages.stringToBytes64(source);
    }

    // ========= Serialize ========= //

    function serializeRouteRegistry(
        RouteRegistryData memory data_
    ) external pure returns (bytes memory) {
        return HyperlaneMailboxMessages.serializeRouteRegistry(
            data_
        );
    }

    function serializeStakeInfo(
        StakeInfoData memory data_
    ) external pure returns (bytes memory) {
        return HyperlaneMailboxMessages.serializeStakeInfo(
            data_
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

    function name(bytes calldata message) external pure returns (string calldata) {
        return message.name();
    }

    function symbol(bytes calldata message) external pure returns (string calldata) {
        return message.symbol();
    }

    function decimals(bytes calldata message) external pure returns (uint8) {
        return message.decimals();
    }

    function routeRegistryMetadata(bytes calldata message) external pure returns (bytes calldata) {
        return message.routeRegistryMetadata();
    }

    // ========= StakeInfo & StakeRedeem  ========= //

    function sender(bytes calldata message) external pure returns (address) {
        return message.sender();
    }

    // ========= StakeInfo ========= //

    function stakeAmount(bytes calldata message) external pure returns (uint256) {
        return message.stakeAmount();
    }

    function sharesAmount(bytes calldata message) external pure returns (uint256) {
        return message.sharesAmount();
    }

    // ========= TokenRedeem  ========= //

    function redeemAmount(bytes calldata message) external pure returns (uint256) {
        return message.redeemAmount();
    }
}
