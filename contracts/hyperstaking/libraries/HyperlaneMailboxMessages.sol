// SPDX-License-Identifier: UNLICENSED
// inspired by Hyperlane: token/libs/TokenMessage.sol
pragma solidity =0.8.27;

import {TypeCasts} from "../../external/hyperlane/libs/TypeCasts.sol";

enum MessageType {
    TokenDeploy,
    TokenBridge,
    RouteRegistry,
    StakeInfo,
    TokenRedeem
}

library HyperlaneMailboxMessages {
    // ========= Helper ========= //

    function stringToBytes32(
        string memory source
    ) internal pure returns (uint8 size, bytes32 result) {
        bytes memory temp = bytes(source);
        if (temp.length == 0) {
            return (0, 0x0);
        }

        require(temp.length <= 32, "stringToBytes32: overflow"); // limitation

        assembly {
            // Load the size of temp
            size := mload(temp)

            // Load next 32 bytes and assign it to result
            result := mload(add(source, 0x20))
        }
    }

    function stringToBytes64(string memory source) internal pure returns (uint8 size, bytes32[2] memory result) {
        bytes memory temp = bytes(source);

        require(temp.length <= 64, "stringToBytes64: overflow"); // limitation
        if (temp.length == 0) {
            return (0, result);
        }

        assembly {
            // Load the size of temp
            size := mload(temp)

            // store the first 32 bytes from temp to result (don't store size)
            mstore(result, mload(add(temp, 0x20)))

            // store the next 32 bytes if size is greater than 32
            if gt(size, 0x20) {
                mstore(add(result, 0x20), mload(add(temp, 0x40)))
            }
        }
    }

    // ========= Serialize ========= //

    function serializeTokenDeploy(
        address strategy_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        bytes memory metadata_
    ) internal pure returns (bytes memory) {
        (uint8 nameSize, bytes32[2] memory nameBytes) = stringToBytes64(name_);
        (uint8 symbolSize, bytes32 symbolBytes) = stringToBytes32(symbol_);

        return abi.encodePacked(
            bytes8(uint64(MessageType.TokenDeploy)),    //  8-bytes: msg type
            TypeCasts.addressToBytes32(strategy_),      // 32-bytes: strategy address
            nameSize,                                   //   1-byte: token name size
            nameBytes,                                  // 64-bytes: token name
            symbolSize,                                 //   1-byte: token symbol size
            symbolBytes,                                // 32-bytes: token symbol
            bytes1(decimals_),                          //   1-byte: token decimals
            metadata_                                   // XX-bytes: additional metadata
        );
    }

    function serializeTokenBridge(
        address strategy_,
        address sender_,
        uint256 stakeAmount_,
        uint256 sharesAmount_,
        bytes memory metadata_
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes8(uint64(MessageType.TokenBridge)),    //  8-bytes: msg type
            TypeCasts.addressToBytes32(strategy_),      // 32-bytes: strategy address
            TypeCasts.addressToBytes32(sender_),        // 32-bytes: sender address
            stakeAmount_,                               // 32-bytes: stake amount
            sharesAmount_,                              // 32-bytes: shares amount
            metadata_                                   // XX-bytes: additional metadata
        );
    }

    function serializeRouteRegistry(
        address strategy_,
        address rwaAsset_,
        bytes memory metadata_
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes8(uint64(MessageType.RouteRegistry)),  //  8-bytes: msg type
            TypeCasts.addressToBytes32(strategy_),      // 32-bytes: strategy address
            TypeCasts.addressToBytes32(rwaAsset_),      // 32-bytes: RWA asset address
            metadata_                                   // XX-bytes: additional metadata
        );
    }

    function serializeStakeInfo(
        address strategy_,
        address sender_,
        uint256 stakeAmount_,
        bytes memory metadata_
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes8(uint64(MessageType.StakeInfo)),      //  8-bytes: msg type
            TypeCasts.addressToBytes32(strategy_),      // 32-bytes: strategy address
            TypeCasts.addressToBytes32(sender_),        // 32-bytes: sender address
            stakeAmount_,                               // 32-bytes: stake amount
            metadata_                                   // XX-bytes: additional metadata
        );
    }

    function serializeTokenRedeem(
        address strategy_,
        address sender_,
        uint256 redeemAmount_,
        bytes memory metadata_
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes8(uint64(MessageType.TokenRedeem)),    //  8-bytes: msg type
            TypeCasts.addressToBytes32(strategy_),      // 32-bytes: strategy address
            TypeCasts.addressToBytes32(sender_),        // 32-bytes: sender address
            redeemAmount_,                              // 32-bytes: amount of shares to reedeem
            metadata_                                   // XX-bytes: additional metadata
        );
    }

    // ========= General ========= //

    /// [0:8]
    function messageType(bytes calldata message) internal pure returns (MessageType) {
        return MessageType(uint64(bytes8(message[0:8])));
    }

    /// [8:40]
    function strategy(bytes calldata message) internal pure returns (address) {
        return TypeCasts.bytes32ToAddress(bytes32(message[8:40]));
    }

    // ========= TokenDeploy ========= //

    /// [40:41][41:105]
    function name(bytes calldata message) internal pure returns (string calldata) {
        uint8 size = uint8(bytes1(message[40:41]));
        return string(bytes(message[41:41 + size]));
    }

    /// [105:106][106:138]
    function symbol(bytes calldata message) internal pure returns (string calldata) {
        uint8 size = uint8(bytes1(message[105:106]));
        return string(bytes(message[106:106 + size]));
    }

    /// [138:139]
    function decimals(bytes calldata message) internal pure returns (uint8) {
        return uint8(bytes1(message[138:139]));
    }

    /// [139:]
    function tokenDeployMetadata(bytes calldata message) internal pure returns (bytes calldata) {
        return message[139:];
    }

    // ========= RouteRegistry ========= //

    function rwaAsset(bytes calldata message) internal pure returns (address) {
        return TypeCasts.bytes32ToAddress(bytes32(message[40:72]));
    }

    function routeRegistryMetadata(bytes calldata message) internal pure returns (bytes calldata) {
        return message[72:];
    }

    // ========= TokenBridge & StakeInfo & TokenRedeem  ========= //

    function sender(bytes calldata message) internal pure returns (address) {
        return TypeCasts.bytes32ToAddress(bytes32(message[40:72]));
    }

    // ========= TokenBridge & StakeInfo ========= //

    function stakeAmount(bytes calldata message) internal pure returns (uint256) {
        return uint256(bytes32(message[72:104]));
    }

    // ========= TokenBridge ========= //

    function sharesAmount(bytes calldata message) internal pure returns (uint256) {
        return uint256(bytes32(message[104:136]));
    }

    function tokenBridgeMetadata(bytes calldata message) internal pure returns (bytes calldata) {
        return message[136:];
    }

    // ========= StakeInfo ========= //

    function stakeInfoMetadata(bytes calldata message) internal pure returns (bytes calldata) {
        return message[104:];
    }

    // ========= TokenRedeem  ========= //

    function redeemAmount(bytes calldata message) internal pure returns (uint256) {
        return uint256(bytes32(message[72:104]));
    }

    function tokenRedeemMetadata(bytes calldata message) internal pure returns (bytes calldata) {
        return message[104:];
    }
}
