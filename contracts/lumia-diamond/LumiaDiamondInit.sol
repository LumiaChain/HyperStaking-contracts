// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {
    IAccessControlEnumerable, AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {IMailbox} from "../external/hyperlane/interfaces/IMailbox.sol";

import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {
    LibInterchainFactory, InterchainFactoryStorage
} from "./libraries/LibInterchainFactory.sol";

/**
 * @title LumiaDiamondInit
 * @dev Initializes Lumia Diamond
 */
contract LumiaDiamondInit is AccessControlEnumerableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    event InterchainFactorySetup(address mailbox);

    /**
     * @notice Setup lumia diamond
     * @dev Grants roles, registers openzeppelin upgradeable contracts, sets hyperlane mailbox
     */
    function init(address mailbox) external initializer {
        __AccessControlEnumerable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        // setup DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // adding IAccessControlEnumerable to supportedInterfaces
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IAccessControlEnumerable).interfaceId] = true;

        // setup interchain factory
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        ifs.mailbox = IMailbox(mailbox);

        emit InterchainFactorySetup(mailbox);
    }
}
