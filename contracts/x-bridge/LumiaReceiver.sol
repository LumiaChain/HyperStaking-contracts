// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IXERC20} from "../external/defi-wonderland/interfaces/IXERC20.sol";


import {ILumiaReceiver} from "./interfaces/ILumiaReceiver.sol";

contract LumiaReceiver is ILumiaReceiver, Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc ILumiaReceiver
    mapping(address xerc20 => uint256) public waitings;

    /// @notice Tokens allowed for processing
    EnumerableSet.AddressSet private registeredTokens;

    /// @notice Address of the Lumia broker
    address public lumiaBroker;

    // ========= Modifiers ========= //

    modifier onlyRegistered(address token_) {
        if (!registeredTokens.contains(token_)) {
            revert NotRegisteredToken(token_);
        }
        _;
    }

    modifier onlyBroker() {
        if (msg.sender != lumiaBroker) {
            revert UnauthorizedBroker(msg.sender);
        }
        _;
    }

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    constructor() Ownable(msg.sender) {}

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//


    // ========= Registered ========= //

    /// @inheritdoc ILumiaReceiver
    function tokensReceived(uint256 amount_) external onlyRegistered(msg.sender) {
        waitings[msg.sender] -= amount_;

        emit TokensReceived(msg.sender, amount_);
    }

    // ========= Broker ========= //

    /// @inheritdoc ILumiaReceiver
    function emitTokens(address token_, uint256 amount_) external onlyBroker {
        require(registeredTokens.contains(token_), NotRegisteredToken(token_));

        waitings[token_] += amount_;

        IXERC20(token_).mint(lumiaBroker, amount_);

        emit TokensEmitted(token_, amount_);
    }

    // ========= Owner ========= //

    /// @inheritdoc ILumiaReceiver
    function updateRegisteredToken(address token_, bool status_) external onlyOwner {
        if (status_) {
            registeredTokens.add(token_);
        } else {
            registeredTokens.remove(token_);
        }

        emit TokenRegistered(token_, status_);
    }

    /**
     * @notice Updates the Lumia broker address
     * @param newBroker_ The new broker address
     */
    function setBroker(address newBroker_) external onlyOwner {
        emit BrokerUpdated(lumiaBroker, newBroker_);
        lumiaBroker = newBroker_;
    }
}
