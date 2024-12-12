// SPDX-License-Identifier: UNLICENSED
// inspired by Hyperlane: token/libs/TokenMessage.sol
pragma solidity =0.8.27;

import {TypeCasts} from "../../external/hyperlane/libs/TypeCasts.sol";

enum MessageType {
    TokenDeploy,
    TokenBridge
}

library HyperlaneMailboxMessages {
    // ========= Helper ========= //

    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        if (temp.length == 0) {
            return 0x0;
        }

        require(temp.length <= 32, "stringToBytes32: overflow"); // limitation

        assembly {
            result := mload(add(source, 32))
        }
    }

    function stringToBytes64(string memory source) internal pure returns (bytes32[2] memory result) {
        bytes memory temp = bytes(source);

        require(temp.length <= 64, "stringToBytes64: overflow"); // limitation

        assembly {
            // load the first 32 bytes into the first array slot
            mstore(add(result, 0x20), mload(add(temp, 0x20)))

            // load the next 32 bytes into the second array slot if applicable
            if gt(mload(temp), 32) {
                mstore(add(result, 0x40), mload(add(temp, 0x40)))
            }
        }
    }

    // ========= Serialize ========= //

    function serializeTokenDeploy(
        address tokenAddress_,
        string memory name_,
        string memory symbol_,
        bytes memory metadata_
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes8(uint64(MessageType.TokenDeploy)),    //  8-bytes: msg type
            TypeCasts.addressToBytes32(tokenAddress_),  // 32-bytes: token address
            stringToBytes64(name_),                     // 64-bytes: token name
            stringToBytes32(symbol_),                   // 32-bytes: token symbol
            metadata_                                   // XX-bytes: additional metadata
        );
    }

    function serializeTokenBridge(
        address vaultToken_,
        address sender_,
        uint256 amount_,
        bytes memory metadata_
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes8(uint64(MessageType.TokenBridge)),    //  8-bytes: msg type
            TypeCasts.addressToBytes32(vaultToken_),    // 32-bytes: vault token address
            TypeCasts.addressToBytes32(sender_),        // 32-bytes: sender address
            amount_,                                    // 32-bytes: amount
            metadata_                                   // XX-bytes: additional metadata
        );
    }

    // ========= General ========= //

    function messageType(bytes calldata message) internal pure returns (MessageType) {
        return MessageType(uint64(bytes8(message[0:8])));
    }

    // ========= TokenDeploy ========= //

    function tokenAddress(bytes calldata message) internal pure returns (address) {
        return TypeCasts.bytes32ToAddress(bytes32(message[8:40]));
    }

    function name(bytes calldata message) internal pure returns (string calldata) {
        return string(bytes(message[40:104]));
    }

    function symbol(bytes calldata message) internal pure returns (string calldata) {
        return string(bytes(message[104:136]));
    }

    function tokenDeployMetadata(
        bytes calldata message
    ) internal pure returns (bytes calldata) {
        return message[136:];
    }

    // ========= TokenBridge ========= //

    function vaultToken(bytes calldata message) internal pure returns (address) {
        return TypeCasts.bytes32ToAddress(bytes32(message[8:40]));
    }

    function sender(bytes calldata message) internal pure returns (address) {
        return TypeCasts.bytes32ToAddress(bytes32(message[40:72]));
    }

    function amount(bytes calldata message) internal pure returns (uint256) {
        return uint256(bytes32(message[72:104]));
    }

    function tokenBridgeMetadata(
        bytes calldata message
    ) internal pure returns (bytes calldata) {
        return message[104:];
    }
}
