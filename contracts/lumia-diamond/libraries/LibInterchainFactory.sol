// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {LumiaAssetToken} from "../LumiaAssetToken.sol";

/// TODO: IERC4626
// import {IERC20 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

/**
 * @notice Stores routing information about specific token route
 * @param exists Helper boolean for easy determination if the route exists
 * @param originDestination The Chain id of the origin
 * @param originLockbox The address of the origin Lockbox
 * @param assetToken The LumiaAssetToken representing stake in a specific strategy
 * @param sharesVault The ERC4626 vault used to mint user shares and handle reward distribution
 */
struct RouteInfo {
    bool exists;
    uint32 originDestination;
    address originLockbox;
    LumiaAssetToken assetToken;
    // IERC4626 sharesVault;
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

    /// @notice Tracks the total state of value reflecting assets locked under a specific strategy
    ///         on the origin chain, showing the total collateral possible to bridge out
    mapping (address strategy => uint256 amount) generalBridgedState;
}

library LibInterchainFactory {
    // -------------------- Errors

    error RouteDoesNotExist(address strategy);

    // -------------------- Constants

    bytes32 constant internal INTERCHAIN_FACTORY_STORAGE_POSITION
        = keccak256("lumia-interchain-factory.storage");

    // 1e18 as a scaling factor, e.g. 0.1 ETH (1e17) == 10%
    uint256 constant internal PERCENT_PRECISION = 1e18; // represent 100%

    // -------------------- Checks

    /// @notice Checks whether route exists
    /// @dev reverts if route does not exist
    function checkRoute(
        InterchainFactoryStorage storage ifs,
        address strategy
    ) internal view {
        require(ifs.routes[strategy].exists, RouteDoesNotExist(strategy));
    }

    // -------------------- Storage Access

    /// @notice Checks whether rwaAsset is valid
    /// @dev reverts if rwaAsset dont some aingv roperties

    function diamondStorage() internal pure returns (InterchainFactoryStorage storage s) {
        bytes32 position = INTERCHAIN_FACTORY_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
