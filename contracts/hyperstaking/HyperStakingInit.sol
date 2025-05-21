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

import {IMailbox} from "../external/hyperlane/interfaces/IMailbox.sol";

import {LibAcl} from "./libraries/LibAcl.sol";
import {LibHyperStaking, HyperStakingStorage, LockboxData} from "./libraries/LibHyperStaking.sol";
import {LibSuperform} from "./libraries/LibSuperform.sol";
import {LibCurve} from "./libraries/LibCurve.sol";

/**
 * @title HyperStakingInit
 * @dev Initializes HyperStaking Diamond
 */
contract HyperStakingInit is AccessControlEnumerableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    error ZeroAddress();

    /**
     * @notice Setup OpenZeppelin upgradeable libraries
     * @dev Grants roles, registers openzeppelin upgradeable contracts, sets hyperlane mailbox
     */
    function init(
        address initStakingManager,
        address initVaultManager,
        address initStrategyManager,
        address lockboxMailbox,
        uint32 lockboxDestination,
        address superformFactory,
        address superformRouter,
        address superPositions,
        address curveRouter
    ) external initializer {
        __AccessControlEnumerable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        // setup DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // setup secondary initial roles
        _grantRole(LibAcl.STAKING_MANAGER_ROLE, initStakingManager);
        _grantRole(LibAcl.VAULT_MANAGER_ROLE, initVaultManager);
        _grantRole(LibAcl.STRATEGY_MANAGER_ROLE, initStrategyManager);

        // adding IAccessControlEnumerable to supportedInterfaces
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IAccessControlEnumerable).interfaceId] = true;

        // initialize storage
        HyperStakingStorage storage v = LibHyperStaking.diamondStorage();

        // withdraw delay, by default 3 days - 259200 seconds
        v.withdrawDelay = 259200;

        // initialize Lockbox
        require(lockboxMailbox != address(0), ZeroAddress());
        LockboxData storage box = v.lockboxData;

        box.destination = lockboxDestination;
        box.mailbox = IMailbox(lockboxMailbox);

        // initialize superform-integration storage
        LibSuperform.init(superformFactory, superformRouter, superPositions);

        // initialize curve-integration storage
        LibCurve.init(curveRouter);
    }
}
