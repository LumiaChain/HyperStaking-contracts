// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ICurveRouterMinimal} from "../strategies/integrations/curve/interfaces/ICurveRouterMinimal.sol";

import { ZeroAddress } from "../Errors.sol";

//================================================================================================//
//                                            Types                                               //
//================================================================================================//

struct PoolConfig {
    address[] tokenList;                    // list of token addresses
    mapping(address => uint8) tokenIndex;   // map from token to index
    mapping(address => bool) tokenExists;   // allow to easy check without looping
}

//================================================================================================//
//                                           Storage                                              //
//================================================================================================//

struct CurveStorage {
    ICurveRouterMinimal curveRouter;
    EnumerableSet.AddressSet swapStrategies;
    mapping(address => PoolConfig) poolsConfig;
}

library LibCurve {
    bytes32 constant internal CURVE_STORAGE_POSITION
        = bytes32(uint256(keccak256("hyperstaking.curve-0.1.storage")) - 1);

    function diamondStorage() internal pure returns (CurveStorage storage s) {
        bytes32 position = CURVE_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    /// initialize this storage
    function init(
        address curveRouter
    ) internal {
        require(curveRouter != address(0), ZeroAddress());

        CurveStorage storage s = LibCurve.diamondStorage();
        s.curveRouter = ICurveRouterMinimal(curveRouter);
    }
}
