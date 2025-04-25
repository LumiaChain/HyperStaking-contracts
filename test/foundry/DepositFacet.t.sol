// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import "forge-std/Test.sol";

import {Diamond} from "../../contracts/diamond/Diamond.sol";
import {DiamondCutFacet} from "../../contracts/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../contracts/diamond/facets/DiamondLoupeFacet.sol";
import {IERC173, OwnershipFacet} from "../../contracts/diamond/facets/OwnershipFacet.sol";

import {IDiamondCut} from "../../contracts/diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../contracts/diamond/interfaces/IDiamondLoupe.sol";

import { LibDiamond } from "../../contracts/diamond/libraries/LibDiamond.sol";
import {DiamondInit} from "../../contracts/diamond/upgradeInitializers/DiamondInit.sol";

// contract DeployDiamond {
// }

contract Deposit is Test {
    Diamond public diamond;

    address public owner;
    address public manager;

    function deployDiamond(address owner_) public returns (Diamond) {
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

        diamond = new Diamond(owner_, address(diamondCutFacet));
        DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();

        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](2);

        // ---

        bytes4[] memory loupeSelectors = new bytes4[](4);
        loupeSelectors[0] = IDiamondLoupe.facets.selector;
        loupeSelectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupe.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupe.facetAddress.selector;

        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });

        // ---

        bytes4[] memory ownershipSelectors = new bytes4[](2);
        ownershipSelectors[0] = IERC173.owner.selector;
        ownershipSelectors[1] = IERC173.transferOwnership.selector;

        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });

        // ---

        DiamondInit diamondInit = new DiamondInit();
        bytes memory initCalldata = abi.encodeWithSelector(DiamondInit.init.selector);

        vm.startPrank(owner);
        LibDiamond.diamondCut(cut, address(diamondInit), initCalldata);
        vm.stopPrank();

        return diamond;
    }

    function deployHyperStaking(address owner_) public {
        deployDiamond(owner_);
    }

    function setUp() public {
        owner = address(1);
        manager = address(2);

        deployHyperStaking(owner);
    }

    function testDeposit1() public {
        vm.startPrank(manager);

        assertTrue(address(diamond) != address(0));

        vm.stopPrank();
    }

}
