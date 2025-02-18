// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LumiaLPToken} from "../LumiaLPToken.sol";
import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IVaultFactory} from "../../external/3adao-lumia/interfaces/IVaultFactory.sol";
import {IVault} from "../../external/3adao-lumia/interfaces/IVault.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

/**
 * @notice Stores routing information about specific token route
 * @param exists Helper boolean for easy determination if the route exists
 * @param isLendingEnabled Indicates whether the asset can be used for lending
 * @param originDestination The Chain id of the origin
 * @param originLockbox The address of the origin Lockbox
 * @param lpToken The token address on this chain representing a HyperStaking position
 * @param lendingVault The 3A DAO Smart Vault address, created for this route
 * @param borrowSafetyBuffer The percentage of collateral to be reserved for safety,
 *        expressed with 18 decimals. For example, 5e16 represents 5% (default value)
 */
struct RouteInfo {
    bool exists;
    bool isLendingEnabled;
    uint32 originDestination;
    address originLockbox;
    LumiaLPToken lpToken;
    IVault lendingVault;
    uint256 borrowSafetyBuffer;
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

    /// @notice 3adao Vault Factory
    IVaultFactory vaultFactory;

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

    // 1e18 as a scaling factor, e.g. 0.1 ETH (1e17) == 10%
    uint256 constant internal PERCENT_PRECISION = 1e18; // represent 100%

    function diamondStorage() internal pure returns (InterchainFactoryStorage storage s) {
        bytes32 position = INTERCHAIN_FACTORY_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
