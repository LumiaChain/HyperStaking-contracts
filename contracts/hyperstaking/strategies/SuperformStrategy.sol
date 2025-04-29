// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IStrategy} from "../interfaces/IStrategy.sol";
import {AbstractStrategy} from "./AbstractStrategy.sol";

import {ISuperformIntegration} from "../interfaces/ISuperformIntegration.sol";
import {ISuperPositions} from "../../external/superform/core/interfaces/ISuperPositions.sol";
import {SuperformFactory} from "../../external/superform/core/SuperformFactory.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165, IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import {Currency} from "../libraries/CurrencyHandler.sol";

/**
 * @title SuperformStrategy
 * @notice This strategy contract uses Superform integration for yield generation
 */
contract SuperformStrategy is AbstractStrategy, IERC1155Receiver {
    using SafeERC20 for IERC20;

    /// Address of the designated SuperVault
    address public immutable SUPER_VAULT;

    /// Specific superform used by this strategy
    uint256 public immutable SUPERFORM_ID;

    /// Token address used in allocation
    IERC20 public immutable STAKE_TOKEN;

    /// Helper type (diamond, superform integration facet)
    ISuperformIntegration public superformIntegration;

    /// Additional helper, which could be determined in the constructor
    ISuperPositions public superPositions;

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error InvalidSuperformCount();
    error InvalidSuperformId();
    error InvalidStakeToken(address expected, address provided);

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    constructor(
        address diamond_,
        address superVault_,
        address stakeToken_
    ) AbstractStrategy(diamond_) {
        superformIntegration = ISuperformIntegration(diamond_);
        SUPER_VAULT = superVault_;

        SuperformFactory factory = SuperformFactory(
            address(superformIntegration.superformFactory())
        );

        try factory.vaultToSuperforms(superVault_, 1) returns (uint256) {
            // Only a single Superform ID should exist; multiple forms are not supported
            revert InvalidSuperformCount();
        } catch {
            /// Superform ID used with this SuperVault, used for routing operations
            SUPERFORM_ID = factory.vaultToSuperforms(superVault_, 0);
        }

        require(factory.isSuperform(SUPERFORM_ID), InvalidSuperformId());

        superPositions = superformIntegration.superPositions();

        /// Ensure stake token matches the underlying asset of the Superform
        require(
            IERC4626(superVault_).asset() == stakeToken_,
            InvalidStakeToken(IERC4626(superVault_).asset(), stakeToken_)
        );

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
        allocation = superformIntegration.singleVaultDeposit(
            SUPERFORM_ID,
            amount_,
            msg.sender,
            address(this)
        );

        // transmute ERC1155A -> ERC20 and approve diamond to fetch the tokens
        superPositions.setApprovalForOne(DIAMOND, SUPERFORM_ID, allocation);
        superformIntegration.transmuteToERC20(
            address(this),
            SUPERFORM_ID,
            allocation,
            address(this)
        );
        // tokens are transmuted 1:1
        IERC20(revenueAsset()).safeIncreaseAllowance(DIAMOND, allocation);

        emit Allocate(user_, amount_, allocation);
    }

    /// @inheritdoc IStrategy
    function exit(
        uint256 shares_,
        address user_
    ) external onlyLumiaDiamond returns (uint256 exitAmount) {
        superformIntegration.transmuteToERC1155A(
            msg.sender,
            SUPERFORM_ID,
            shares_,
            msg.sender
        );

        exitAmount = superformIntegration.singleVaultWithdraw(
            SUPERFORM_ID,
            shares_,
            msg.sender,
            msg.sender
        );

        emit Exit(user_, shares_, exitAmount);
    }

    // ========= View ========= //

    /// @inheritdoc IStrategy
    function stakeCurrency() external view returns(Currency memory) {
        return Currency({
            token: address(STAKE_TOKEN)
        });
    }

    /// @inheritdoc IStrategy
    function revenueAsset() public view returns(address) {
        return superformIntegration.aERC20Token(SUPERFORM_ID);
    }

    /// @inheritdoc IStrategy
    function previewAllocation(uint256 stakeAmount_) external view returns (uint256) {
        return superformIntegration.previewDepositTo(SUPERFORM_ID, stakeAmount_);
    }

    /// @inheritdoc IStrategy
    function previewExit(uint256 assetAllocation_) external view returns (uint256 stakeAmount) {
        return superformIntegration.previewWithdrawFrom(SUPERFORM_ID, assetAllocation_);
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    )
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    )
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
