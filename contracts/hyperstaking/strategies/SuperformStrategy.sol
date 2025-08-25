// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {StrategyKind, StrategyRequest, IStrategy} from "../interfaces/IStrategy.sol";
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
    IERC20 public immutable SUPERFORM_INPUT_TOKEN;

    /// Superform integration - (diamond facet)
    ISuperformIntegration public superformIntegration;

    /// SuperPositions contract address
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
        address stakeToken_ // SuperUSDC supports USDC as deposit, asset is checked
    ) AbstractStrategy(diamond_) {
        require(superVault_ != address(0), ZeroAddress());
        require(stakeToken_ != address(0), ZeroAddress());

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

        SUPERFORM_INPUT_TOKEN = IERC20(stakeToken_);
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Diamond ========= //

    function requestAllocation(
        uint256 requestId_,
        uint256 amount_,
        address user_
    ) public payable virtual onlyLumiaDiamond returns (uint64 readyAt) {
        require(amount_ > 0, ZeroAmount());

        readyAt = 0; // claimable immediately
        _storeAllocationRequest(
            requestId_,
            user_,
            amount_,
            readyAt
        );

        emit AllocationRequested(requestId_, user_, amount_, readyAt);
    }

    /// @inheritdoc IStrategy
    function claimAllocation(
        uint256[] calldata ids_, address receiver_
    ) public virtual onlyLumiaDiamond returns (uint256 allocation) {
        require(ids_.length == 1, DontSupportArrays());
        uint256 id = ids_[0];

        StrategyRequest memory r = _loadClaimable(id, StrategyKind.Allocation);
        _markClaimed(id);

        allocation = superformIntegration.singleVaultDeposit(
            SUPERFORM_ID,
            r.amount,
            msg.sender,
            address(this)
        );

        // transmute ERC1155A -> ERC20 and approve integration to fetch the tokens
        superPositions.setApprovalForOne(address(superformIntegration), SUPERFORM_ID, allocation);

        // tokens are transmuted 1:1
        superformIntegration.transmuteToERC20(
            address(this),
            SUPERFORM_ID,
            allocation,
            address(this)
        );

        // transfer allocation
        IERC20(revenueAsset()).safeTransfer(receiver_, allocation);

        emit AllocationClaimed(id, receiver_, allocation);
    }

    /// @inheritdoc IStrategy
    function requestExit(
        uint256 requestId_,
        uint256 shares_,
        address user_
    ) public virtual onlyLumiaDiamond returns (uint64 readyAt) {
        require(shares_ > 0, ZeroAmount());

        readyAt = 0; // claimable immediately
        _storeExitRequest(
            requestId_,
            user_,
            shares_,
            readyAt
        );

        emit ExitRequested(requestId_, user_, shares_, readyAt);
    }

    /// @inheritdoc IStrategy
    function claimExit(
        uint256[] calldata ids_, address receiver_
    ) public virtual onlyLumiaDiamond returns (uint256 exitAmount) {
        require(ids_.length == 1, DontSupportArrays());
        uint256 id = ids_[0];

        StrategyRequest memory r = _loadClaimable(id, StrategyKind.Exit);
        _markClaimed(id);

        superformIntegration.transmuteToERC1155A(
            msg.sender,
            SUPERFORM_ID,
            r.amount,
            msg.sender
        );

        exitAmount = superformIntegration.singleVaultWithdraw(
            SUPERFORM_ID,
            r.amount,
            receiver_,
            receiver_
        );

        emit ExitClaimed(id, receiver_, exitAmount);
    }

    /// @inheritdoc IStrategy
    function isIntegratedStakeStrategy() external pure virtual override returns (bool) {
        return true;
    }

    // ========= View ========= //

    /// @inheritdoc IStrategy
    function stakeCurrency() public view virtual returns(Currency memory) {
        return Currency({
            token: address(SUPERFORM_INPUT_TOKEN)
        });
    }

    /// @inheritdoc IStrategy
    function revenueAsset() public view virtual returns(address) {
        return superformIntegration.aERC20Token(SUPERFORM_ID);
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

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Uses superformIntegration to preview allocation
    function _previewAllocationRaw(uint256 stake_) internal view virtual override returns (uint256) {
        return superformIntegration.previewDepositTo(SUPERFORM_ID, stake_);
    }

    /// @notice Uses superformIntegration to preview exit
    function _previewExitRaw(uint256 allocation_) internal view virtual override returns (uint256) {
        return superformIntegration.previewRedeemFrom(SUPERFORM_ID, allocation_);
    }
}
