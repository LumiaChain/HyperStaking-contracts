// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract LumiaReceiver is Ownable2Step {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Token address -> amount of tokens waiting to be bridged
    mapping(address => uint256) public waitings;

    /// @notice Tokens allowed for processing (enumerable set can be added later)
    EnumerableSet.AddressSet private registeredTokens;

    /// @notice Address of the Lumia broker
    address public lumiaBroker;

    // ========= Errors ========= //

    error NotRegisteredToken(address token);
    error UnauthorizedBroker(address sender);

    // ========= Events ========= //

    event TokenRegistered(address indexed token, bool status);
    event TokensReceived(address indexed token, uint256 amount);
    event TokensEmitted(address indexed token, uint256 amount);
    event BrokerUpdated(address indexed oldBroker, address indexed newBroker);

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

    /**
     * @notice Records tokens received from bridging
     * @param amount_ The amount of tokens received
     */
    function tokensReceived(uint256 amount_) external onlyRegistered(msg.sender) {
        waitings[msg.sender] -= amount_;

        emit TokensReceived(msg.sender, amount_);
    }

    // ========= Broker ========= //

    /**
     * @notice Emits tokens to the broker for further processing
     * @param token_ The token address to emit
     * @param amount_ The amount of tokens to emit
     */
    function emitTokens(address token_, uint256 amount_) external onlyBroker {
        require(registeredTokens.contains(token_), NotRegisteredToken(token_));

        waitings[token_] += amount_;
        IERC20(token_).safeTransfer(lumiaBroker, amount_);

        emit TokensEmitted(token_, amount_);
    }

    // ========= Owner ========= //

    /**
     * @notice Updates the registration status of a token
     * @param token_ The token address to register or unregister
     * @param status_ The registration status (true to register, false to unregister)
     */
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
        lumiaBroker = newBroker_;
        emit BrokerUpdated(lumiaBroker, newBroker_);
    }
}
