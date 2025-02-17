// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LumiaLPToken} from "../LumiaLPToken.sol";
import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

/**
 * @notice Stores routing information about specific token route
 * @param exists Helper boolean for easy determination if the route exists
 * @param originLockbox The address of the origin Lockbox
 * @param originDestination The Chain id of the origin
 * @param lpToken The token address on this chain representing a HyperStaking position
 // * @param lendingVault The 3A DAO Vault address, created for this route
 */
struct RouteInfo {
    bool exists;
    address originLockbox;
    uint32 originDestination;
    LumiaLPToken lpToken;
//    address lendingVault;
}

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

    /// @notice Temporary data about last msg
    LastMessage lastMessage;

    /// @notice Set of authorized Lockboxes (located on their respective origin chains)
    EnumerableSet.AddressSet authorizedOrigins;

    /// @notice Maps an origin address to its corresponding destination chain ID
    mapping (address origin => uint32) destinations;

    /// @notice Mapping of strategy to its detailed route information
    mapping (address strategy => RouteInfo) routes;
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

