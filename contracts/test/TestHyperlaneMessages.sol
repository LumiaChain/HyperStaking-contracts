// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {
    MessageType,
    RouteRegistryData,
    StakeInfoData,
    StakeRewardData,
    StakeRedeemData,
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

    function serializeStakeReward(
        StakeRewardData memory data_
    ) external pure returns (bytes memory) {
        return HyperlaneMailboxMessages.serializeStakeReward(
            data_
        );
    }

    function serializeStakeRedeem(
        StakeRedeemData memory data_
    ) external pure returns (bytes memory) {
        return HyperlaneMailboxMessages.serializeStakeRedeem(
            data_
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

    function stake(bytes calldata message) external pure returns (uint256) {
        return message.stake();
    }

    // ========= StakeReward ========= //

    function stakeAdded(bytes calldata message) external pure returns (uint256) {
        return message.stakeAdded();
    }

    // ========= TokenRedeem  ========= //

    function redeemAmount(bytes calldata message) external pure returns (uint256) {
        return message.redeemAmount();
    }
}
