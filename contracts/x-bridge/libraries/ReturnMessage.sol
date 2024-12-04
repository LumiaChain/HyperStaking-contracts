// SPDX-License-Identifier: UNLICENSED
// inspired by Hyperlane: token/libs/TokenMessage.sol
pragma solidity =0.8.27;

library ReturnMessage {
    function serialize(
        bytes32 sender_,
        uint256 returnAmount_,
        bytes memory metadata_
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(sender_, returnAmount_, metadata_);
    }

    function returnSender(bytes calldata message) internal pure returns (bytes32) {
        return bytes32(message[0:32]);
    }

    function returnAmount(bytes calldata message) internal pure returns (uint256) {
        return uint256(bytes32(message[32:64]));
    }

    function metadata(
        bytes calldata message
    ) internal pure returns (bytes calldata) {
        return message[64:];
    }
}
