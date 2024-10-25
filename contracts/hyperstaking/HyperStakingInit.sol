// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";

import {
    IAccessControlEnumerable, AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

/**
 * @title HyperStakingInit
 * @dev Initializes HyperStaking Diamond
 */
contract HyperStakingInit is AccessControlEnumerableUpgradeable {

    /**
     * @notice Setup initial roles and interfaces for the Diamond.
     * @dev Grants `DEFAULT_ADMIN_ROLE` to the deployer and registers
     *      the `IAccessControlEnumerable` interface.
     */
    function init() external {
        // setup DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // adding IAccessControlEnumerable to supportedInterfaces
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IAccessControlEnumerable).interfaceId] = true;
    }
}
