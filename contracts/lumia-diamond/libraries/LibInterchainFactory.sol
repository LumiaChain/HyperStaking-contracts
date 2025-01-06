// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

struct LastMessage {
    address sender;
    bytes data;
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct InterchainFactoryStorage {
    /// @notice Hyperlane Mailbox
    IMailbox mailbox;

    /// @notice ChainID - route destination to origin chain
    uint32 destination;

    /// @notice Address of the sender - Lockbox located on the origin chain
    address originLockbox;

    /// @notice Enumerable map storing the relation between origin vaultTokens and minted lpTokens
    EnumerableMap.AddressToAddressMap tokensMap;

    /// @notice Temporary data about last msg
    LastMessage lastMessage;
}

library LibInterchainFactory {
    bytes32 constant internal INTERCHAIN_FACTORY_STORAGE_POSITION
        = keccak256("lumia-interchain-factory.storage");

    function diamondStorage() internal pure returns (InterchainFactoryStorage storage s) {
        bytes32 position = INTERCHAIN_FACTORY_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}

