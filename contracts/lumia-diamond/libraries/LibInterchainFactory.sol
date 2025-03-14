// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IMailbox} from "../../external/hyperlane/interfaces/IMailbox.sol";
import {IMintableToken} from "../../external/3adao-lumia/interfaces/IMintableToken.sol";
import {IMintableTokenOwner} from "../../external/3adao-lumia/interfaces/IMintableTokenOwner.sol";
import {MintableTokenOwner} from "../../external/3adao-lumia/gobernance/MintableTokenOwner.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

/**
 * @notice Stores routing information about specific token route
 * @param exists Helper boolean for easy determination if the route exists
 * @param originDestination The Chain id of the origin
 * @param originLockbox The address of the origin Lockbox
 * @param rwaAssetOwner The MintableTokenOwner contract, owner contract of rwaAsset
 * @param rwaAsset The MintableToken contract representing the Real-World Asset
 */
struct RouteInfo {
    bool exists;
    uint32 originDestination;
    address originLockbox;
    IMintableTokenOwner rwaAssetOwner;
    IMintableToken rwaAsset;
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

    /// @notice Tracks the amount of assets a user has bridged for a given strategy,
    ///         reflecting both deposits and redemptions
    mapping (address strategy => mapping(address user => uint256)) userBridgedState;

    /// @notice Tracks the migration status between strategies, maps the source strategy (`from`)
    ///         to the destination strategy (`to`), and stores the amount being migrated
    mapping (address from => mapping(address to => uint256 amount)) migrationsState;
}

library LibInterchainFactory {
    // -------------------- Errors

    error RouteDoesNotExist(address strategy);

    error InvalidRwaAsset(address badRwaAsset);
    error NotOwnableRwaAsset(address badRwaAsset);
    error NotMintableRwaAsset(address badRwaAsset);

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

    /// @notice Verifies properties of the RWA asset
    /// @dev reverts if invalid
    function checkRwaAsset(address rwaAsset) internal view {
        require(
            rwaAsset != address(0) && rwaAsset.code.length > 0,
            InvalidRwaAsset(rwaAsset)
        );

        // additional check if the token has an owner (MintableTokenOwner)
        (bool success, ) = rwaAsset.staticcall(abi.encodeWithSignature("owner()"));
        require(success, NotOwnableRwaAsset(rwaAsset));


        // expect this contract to have the right to mint
        MintableTokenOwner rwaAssetOwner = MintableTokenOwner(IMintableToken(rwaAsset).owner());
        require(rwaAssetOwner.minters(address(this)), NotMintableRwaAsset(rwaAsset));
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
