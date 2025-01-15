// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../interfaces/IStrategy.sol";

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
    address public immutable SUPERFORM_ID;

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
        address superformId_,
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
        uint256 stakeAmount_,
        address user_
    ) external payable returns (uint256 allocation) {

    }

    /// @inheritdoc IStrategy
    function exit(uint256 assetAllocation_, address user_) external returns (uint256 exitAmount) {

    }

    /// @inheritdoc IStrategy
    function revenueAsset() external view returns(address) {
    }

    /// @inheritdoc IStrategy
    function previewAllocation(uint256 stakeAmount_) external view returns (uint256 allocation) {

    }

    /// @inheritdoc IStrategy
    function previewExit(uint256 assetAllocation_) external view returns (uint256 stakeAmount) {
    }
}
