// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {
    IAccessControlEnumerable, AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title HyperStakingInit
 * @dev Initializes HyperStaking Diamond
 */
contract HyperStakingInit is AccessControlEnumerableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    /**
     * @notice Setup OpenZeppelin upgradeable libraries
     * @dev Grants `DEFAULT_ADMIN_ROLE` to the deployer and registers
     *      the `IAccessControlEnumerable` interface.
     */
    function init() external initializer {
        __AccessControlEnumerable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        // setup DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // adding IAccessControlEnumerable to supportedInterfaces
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IAccessControlEnumerable).interfaceId] = true;
    }
}
