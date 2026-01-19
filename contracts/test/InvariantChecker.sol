// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IAllocation} from "../hyperstaking/interfaces/IAllocation.sol";
import {ILockbox} from "../hyperstaking/interfaces/ILockbox.sol";
import {IHyperlaneHandler} from "../lumia-diamond/interfaces/IHyperlaneHandler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {StakeInfo} from "../hyperstaking/libraries/LibHyperStaking.sol";
import {FailedRedeem} from "../hyperstaking/libraries/LibHyperStaking.sol";
import {RouteInfo} from "../lumia-diamond/libraries/LibInterchainFactory.sol";

import "hardhat/console.sol";

/// @title InvariantChecker
/// @notice Minimal checker used in tests to assert basic HyperStaking invariants
contract InvariantChecker {
    /// @notice Allocation facet used to read per-strategy StakeInfo
    IAllocation public allocationFacet;

    /// @notice Lockbox facet used to read per-strategy lockbox data
    ILockbox public lockboxFacet;

    /// @notice Hyperlane handler facet used to resolve strategy routing info
    IHyperlaneHandler public hyperlaneHandlerFacet;

    /// @notice Strategies tracked by this checker
    address[] public strategies;
    mapping(address => bool) public isStrategy;

    /// @notice Principal token on Lumia for a given strategy
    mapping(address => IERC20) public lumiaPrincipalOf;

    constructor(address allocationFacet_, address lockboxFacet_, address hyperlaneHandlerFacet_) {
        allocationFacet = IAllocation(allocationFacet_);
        lockboxFacet = ILockbox(lockboxFacet_);
        hyperlaneHandlerFacet = IHyperlaneHandler(hyperlaneHandlerFacet_);
    }

    /// @notice Start tracking a strategy and bind its Lumia principal token
    function addStrategy(address strategy) public {
        require(strategy != address(0), "strategy=0");
        require(!isStrategy[strategy], "already added");

        RouteInfo memory ri = hyperlaneHandlerFacet.getRouteInfo(strategy);
        require(address(ri.assetToken) != address(0), "no principal");

        isStrategy[strategy] = true;
        strategies.push(strategy);
        lumiaPrincipalOf[strategy] = ri.assetToken;
    }

    /// @notice Batch variant of addStrategy
    function addStrategies(address[] calldata list) external {
        for (uint256 i = 0; i < list.length; i++) addStrategy(list[i]);
    }

    /// @notice Sum failed redeem amounts for a given strategy
    /// @return sum total amount across all failed redeems for strategy
    function sumFailedRedeems(address strategy)
        public
        view
        returns (uint256 sum)
    {
        uint256 n = lockboxFacet.getFailedRedeemCount();
        if (n == 0) return 0;

        uint256[] memory ids = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            ids[i] = i;
        }

        FailedRedeem[] memory fr = lockboxFacet.getFailedRedeems(ids);

        for (uint256 i = 0; i < fr.length; i++) {
            if (fr[i].strategy == strategy) sum += fr[i].amount;
        }
    }

    /// @notice Assert invariants for all tracked strategies
    function check() external view {
        require(strategies.length > 0, "no strategies");

        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];

            uint256 failedRedeemsStake = sumFailedRedeems(strategy);

            // cannot have more pending exits than total stake
            StakeInfo memory si = allocationFacet.stakeInfo(strategy);
            require(
                si.totalStake >= (
                    si.pendingExitStake + si.pendingDepositStake + failedRedeemsStake
                ),
                "inv: totalStake < pendingStake"
            );

            uint256 available = si.totalStake - (
                si.pendingExitStake + si.pendingDepositStake + failedRedeemsStake
            );

            // principal token supply mirrors available stake on Lumia
            IERC20 principal = lumiaPrincipalOf[strategy];
            require(address(principal) != address(0), "principal not set");

            uint256 supply = principal.totalSupply();

            // dbg print mismatch in tests
            if (supply != available) {
                console.log("dbg: stake available       :", available);
                console.log("dbg: pending stake         :", si.pendingExitStake);
                console.log("dbg: pending deposit stake :", si.pendingDepositStake);
                console.log("dbg: failed redeem stake   :", failedRedeemsStake);
                console.log("dbg: principal supply      :", supply);
            }

            // supply must match available stake
            require(supply == available, "inv: principalSupply != availableStake");
        }
    }
}
