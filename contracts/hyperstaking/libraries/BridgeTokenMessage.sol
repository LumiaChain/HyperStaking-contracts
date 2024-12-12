// SPDX-License-Identifier: UNLICENSED
// inspired by Hyperlane: token/libs/TokenMessage.sol
pragma solidity =0.8.27;

library BridgeTokenMessage {
    function serialize(
        bytes32 vaultToken_,
        bytes32 sender_,
        uint256 amount_,
        bytes memory metadata_
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(sender_, vaultToken_, amount_, metadata_);
    }

    function vaultToken(bytes calldata message) internal pure returns (bytes32) {
        return bytes32(message[0:32]);
    }

    function sender(bytes calldata message) internal pure returns (bytes32) {
        return bytes32(message[32:64]);
    }

    function amount(bytes calldata message) internal pure returns (uint256) {
        return uint256(bytes32(message[64:96]));
    }

    function metadata(
        bytes calldata message
    ) internal pure returns (bytes calldata) {
        return message[9:];
    }
}
