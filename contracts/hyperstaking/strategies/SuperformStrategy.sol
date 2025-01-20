// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../interfaces/IStrategy.sol";
import {ISuperformIntegration} from "../interfaces/ISuperformIntegration.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SuperformStrategy
 * @notice This strategy contract uses Superform integration for yield generation.
 */
contract SuperformStrategy is IStrategy {
    using SafeERC20 for IERC20;

    /// Lumia Diamond Proxy address
    address public immutable DIAMOND;

    /// Specific superform used by this strategy
    uint256 public immutable SUPERFORM_ID;

    // Token address used in allocation
    IERC20 public immutable STAKE_TOKEN;

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error NotLumiaDiamond();

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    modifier onlyLumiaDiamond() {
        require(msg.sender == DIAMOND, NotLumiaDiamond());
        _;
    }

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//
    constructor(
        address diamond_,
        uint256 superformId_,
        address stakeToken_
    ) {
        DIAMOND = diamond_;
        SUPERFORM_ID = superformId_;
        STAKE_TOKEN = IERC20(stakeToken_);
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Diamond ========= //

    /// @inheritdoc IStrategy
    function allocate(
        uint256 amount_,
        address user_
    ) external payable onlyLumiaDiamond returns (uint256 allocation) {
        allocation = ISuperformIntegration(DIAMOND).singleVaultDeposit(
            SUPERFORM_ID,
            amount_,
            msg.sender,
            address(this)
        );

        ISuperformIntegration(DIAMOND).transmuteToERC20(
            address(this),
            SUPERFORM_ID,
            allocation,
            msg.sender
        );

        emit Allocate(user_, amount_, allocation);
    }

    /// @inheritdoc IStrategy
    function exit(uint256 shares_, address user_) external returns (uint256 exitAmount) {
        ISuperformIntegration(DIAMOND).transmuteToERC1155A(
            msg.sender,
            SUPERFORM_ID,
            shares_,
            address(this)
        );

        exitAmount = ISuperformIntegration(DIAMOND).singleVaultWithdraw(
            SUPERFORM_ID,
            shares_,
            msg.sender,
            msg.sender
        );

        emit Exit(user_, shares_, exitAmount);
    }

    /// @inheritdoc IStrategy
    function revenueAsset() external view returns(address) {
        return ISuperformIntegration(DIAMOND).aERC20Token(SUPERFORM_ID);
    }

    /// @inheritdoc IStrategy
    function previewAllocation(uint256 stakeAmount_) external view returns (uint256) {
        return ISuperformIntegration(DIAMOND).previewDepositTo(SUPERFORM_ID, stakeAmount_);
    }

    /// @inheritdoc IStrategy
    function previewExit(uint256 assetAllocation_) external view returns (uint256 stakeAmount) {
        return ISuperformIntegration(DIAMOND).previewWithdrawFrom(SUPERFORM_ID, assetAllocation_);
    }
}
