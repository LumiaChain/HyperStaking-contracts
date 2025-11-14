// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ICurveRouterMinimal} from "../strategies/integrations/curve/interfaces/ICurveRouterMinimal.sol";

import { ZeroAddress } from "../../shared/Errors.sol";

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

    error CurveRouterNotSet();

    function diamondStorage() internal pure returns (CurveStorage storage s) {
        bytes32 position = CURVE_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    /// @notice Ensures Curve router is configured
    function requireRouter() internal view {
        CurveStorage storage s = diamondStorage();
        require(
            address(s.curveRouter) != address(0),
            CurveRouterNotSet()
        );
    }

    /// @notice Sets Curve router address
    function setRouter(
        address curveRouter
    ) internal {
        require(curveRouter != address(0), ZeroAddress());

        CurveStorage storage s = LibCurve.diamondStorage();
        s.curveRouter = ICurveRouterMinimal(curveRouter);
    }
}
