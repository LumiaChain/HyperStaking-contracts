// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IBaseRouterImplementation} from "../../external/superform/core/interfaces/IBaseRouterImplementation.sol";
import {ISuperformFactory} from "../../external/superform/core/interfaces/ISuperformFactory.sol";
import {ISuperPositions} from "../../external/superform/core/interfaces/ISuperPositions.sol";

import {LibDiamond} from "../../diamond/libraries/LibDiamond.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct SuperformStorage {
    EnumerableSet.AddressSet superformStrategies;
    uint256 maxSlippage; // where 10000 = 100%

    ISuperformFactory superformFactory;
    IBaseRouterImplementation superformRouter;
    ISuperPositions superPositions;
}

library LibSuperform {
    bytes32 constant internal SUPERFORM_STORAGE_POSITION
        = bytes32(uint256(keccak256("hyperstaking.superform-0.1.storage")) - 1);

    error ZeroAddress();

    function diamondStorage() internal pure returns (SuperformStorage storage s) {
        bytes32 position = SUPERFORM_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    /// initialize this storage
    function init(
        address superformFactory,
        address superformRouter,
        address superPositions
    ) internal {
        require(superformFactory != address(0), ZeroAddress());
        require(superformRouter != address(0), ZeroAddress());
        require(superPositions != address(0), ZeroAddress());

        SuperformStorage storage s = LibSuperform.diamondStorage();

        s.superformFactory = ISuperformFactory(superformFactory);
        s.superformRouter = IBaseRouterImplementation(superformRouter);
        s.superPositions = ISuperPositions(superPositions);
        s.maxSlippage = 50; // default value: 0.5%

        // add IERC1155Receiver to supportedInterfaces
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC1155Receiver).interfaceId] = true;
    }
}
