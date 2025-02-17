// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {
    MessageType, HyperlaneMailboxMessages
} from "../hyperstaking/libraries/HyperlaneMailboxMessages.sol";

/// @notice Test wrapper for HyperlaneMailboxMessages library
contract TestHyperlaneMessages {
    using HyperlaneMailboxMessages for bytes;

    // ========= Helper ========= //

    function stringToBytes32(string memory source) external pure returns (uint8 size, bytes32 result) {
        return HyperlaneMailboxMessages.stringToBytes32(source);
    }

    function stringToBytes64(string memory source) external pure returns (uint8 size, bytes32[2] memory result) {
        return HyperlaneMailboxMessages.stringToBytes64(source);
    }

    // ========= Serialize ========= //

    function serializeTokenDeploy(
        address strategy_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        bytes memory metadata_
    ) external pure returns (bytes memory) {
        return HyperlaneMailboxMessages.serializeTokenDeploy(
            strategy_,
            name_,
            symbol_,
            decimals_,
            metadata_
        );
    }

    function serializeTokenBridge(
        address strategy_,
        address sender_,
        uint256 stakeAmount_,
        uint256 sharesAmount_,
        bytes memory metadata_
    ) external pure returns (bytes memory) {
        return HyperlaneMailboxMessages.serializeTokenBridge(
            strategy_,
            sender_,
            stakeAmount_,
            sharesAmount_,
            metadata_
        );
    }

    function serializeTokenRedeem(
        address strategy_,
        address sender_,
        uint256 amount_,
        bytes memory metadata_
    ) external pure returns (bytes memory) {
        return HyperlaneMailboxMessages.serializeTokenRedeem(
            strategy_,
            sender_,
            amount_,
            metadata_
        );
    }

    // ========= General ========= //

    function messageType(bytes calldata message) external pure returns (MessageType) {
        return message.messageType();
    }

    function strategy(bytes calldata message) external pure returns (address) {
        return message.strategy();
    }

    // ========= TokenDeploy ========= //


    function name(bytes calldata message) external pure returns (string calldata) {
        return message.name();
    }

    function symbol(bytes calldata message) external pure returns (string calldata) {
        return message.symbol();
    }

    function decimals(bytes calldata message) external pure returns (uint8) {
        return message.decimals();
    }

    function tokenDeployMetadata(bytes calldata message) external pure returns (bytes calldata) {
        return message.tokenDeployMetadata();
    }

    // ========= TokenBridge & TokenRedeem  ========= //

    function sender(bytes calldata message) external pure returns (address) {
        return message.sender();
    }

    // ========= TokenBridge ========= //

    function stakeAmount(bytes calldata message) external pure returns (uint256) {
        return message.stakeAmount();
    }

    function sharesAmount(bytes calldata message) external pure returns (uint256) {
        return message.sharesAmount();
    }

    function tokenBridgeMetadata(bytes calldata message) external pure returns (bytes calldata) {
        return message.tokenBridgeMetadata();
    }

    // ========= TokenRedeem  ========= //

    function redeemAmount(bytes calldata message) external pure returns (uint256) {
        return message.redeemAmount();
    }

    function tokenRedeemMetadata(bytes calldata message) external pure returns (bytes calldata) {
        return message.tokenRedeemMetadata();
    }
}
