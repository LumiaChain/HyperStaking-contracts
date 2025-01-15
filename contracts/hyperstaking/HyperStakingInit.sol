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

import {IBaseRouterImplementation} from "../external/superform/core/interfaces/IBaseRouterImplementation.sol";
import {ISuperformFactory} from "../external/superform/core/interfaces/ISuperformFactory.sol";
import {ISuperPositions} from "../external/superform/core/interfaces/ISuperPositions.sol";

import {IMailbox} from "../external/hyperlane/interfaces/IMailbox.sol";

import {LibAcl} from "./libraries/LibAcl.sol";
import {LibStrategyVault, LockboxData} from "./libraries/LibStrategyVault.sol";
import {LibSuperform, SuperformStorage} from "./libraries/LibSuperform.sol";


/**
 * @title HyperStakingInit
 * @dev Initializes HyperStaking Diamond
 */
contract HyperStakingInit is AccessControlEnumerableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    error ZeroAddress();

    /**
     * @notice Setup OpenZeppelin upgradeable libraries
     * @dev Grants `DEFAULT_ADMIN_ROLE` to the deployer and registers
     *      the `IAccessControlEnumerable` interface.
     */
    function init(
        address initStakingManager,
        address initStrategyVaultManager,
        address lockboxMailbox,
        uint32 lockboxDestination,
        address superformFactory,
        address superformRouter,
        address superPositions
    ) external initializer {
        __AccessControlEnumerable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        // setup DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // setup secondary initial roles
        _grantRole(LibAcl.STAKING_MANAGER_ROLE, initStakingManager);
        _grantRole(LibAcl.STRATEGY_VAULT_MANAGER_ROLE, initStrategyVaultManager);

        // adding IAccessControlEnumerable to supportedInterfaces
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IAccessControlEnumerable).interfaceId] = true;

        // initialize Lockbox

        require(lockboxMailbox != address(0), ZeroAddress());
        LockboxData storage box = LibStrategyVault.diamondStorage().lockboxData;

        box.destination = lockboxDestination;
        box.mailbox = IMailbox(lockboxMailbox);

        // initialize Superform integration

        require(superformFactory != address(0), ZeroAddress());
        require(superformRouter != address(0), ZeroAddress());
        require(superPositions != address(0), ZeroAddress());
        SuperformStorage storage ss = LibSuperform.diamondStorage();

        ss.superformFactory = ISuperformFactory(superformFactory);
        ss.superformRouter = IBaseRouterImplementation(superformRouter);
        ss.superPositions = ISuperPositions(superPositions);
        ss.maxSlippage = 50; // 0.5%
    }
}
