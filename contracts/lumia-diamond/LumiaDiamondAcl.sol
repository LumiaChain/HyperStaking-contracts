// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {IMailbox} from "../external/hyperlane/interfaces/IMailbox.sol";

import {LibInterchainFactory} from "./libraries/LibInterchainFactory.sol";

/**
 * @title LumiaDimondAcl
 * @dev Defines access control within Lumia diamond
 *
 *      Utilizes OpenZeppelin's AccessControlEnumerableUpgradeable version with
 *      EIP-7201 namespace storage, making it compatible with Diamond Proxy architecture
 *
 *      Facets can inherit and use the provided role-based modifiers
 */
contract LumiaDiamondAcl is AccessControlEnumerableUpgradeable {
    //============================================================================================//
    //                                         Constants                                          //
    //============================================================================================//

    bytes32 public constant LUMIA_FACTORY_MANAGER_ROLE = keccak256("LUMIA_FACTORY_MANAGER_ROLE");
    bytes32 public constant LUMIA_REWARD_MANAGER_ROLE = keccak256("LUMIA_REWARD_MANAGER_ROLE");

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error OnlyDiamondInternal();
    error NotFromMailbox(address from);
    error OnlyLumiaFactoryManager();
    error OnlyLumiaRewardManager();

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    /// @dev Prevents calling a function from anyone not being the Diamond contract itself.
    modifier diamondInternal() {
        require(msg.sender == address(this), OnlyDiamondInternal());
        _;
    }

    /// @notice Only accept messages from a Hyperlane Mailbox contract
    modifier onlyMailbox() {
        IMailbox mailbox = LibInterchainFactory.diamondStorage().mailbox;
        require(
            msg.sender == address(mailbox),
            NotFromMailbox(msg.sender)
        );
        _;
    }

    /// @dev Only allows access for the `Lumia Factory Manager` role.
    modifier onlyLumiaFactoryManager() {
        if (!hasRole(LUMIA_FACTORY_MANAGER_ROLE, msg.sender)) {
            revert OnlyLumiaFactoryManager();
        }
        _;
    }

    /// @dev Only allows access for the `Lumia Reward Manager` role.
    modifier onlyLumiaRewardManager() {
        if (!hasRole(LUMIA_REWARD_MANAGER_ROLE, msg.sender)) {
            revert OnlyLumiaRewardManager();
        }
        _;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= View ========= //

    /// @notice Helper function used by an external rewarder
    function hasLumiaRewardManagerRole(address account) external view returns (bool) {
        return hasRole(LUMIA_REWARD_MANAGER_ROLE, account);
    }
}
