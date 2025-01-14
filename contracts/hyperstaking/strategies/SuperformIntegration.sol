// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBaseRouterImplementation} from "../../external/superform/core/interfaces/IBaseRouterImplementation.sol";
import {ISuperformFactory} from "../../external/superform/core/interfaces/ISuperformFactory.sol";
import {ISuperPositions} from "../../external/superform/core/interfaces/ISuperPositions.sol";
import {IBaseForm} from "../../external/superform/core/interfaces/IBaseForm.sol";

import {SingleDirectSingleVaultStateReq, SingleVaultSFData, LiqRequest} from "../../external/superform/core/types/DataTypes.sol";
import {DataLib} from "../../external/superform/core/libraries/DataLib.sol";

/**
 * @title SuperformIntegration
 * @dev Integration with Superform, providing deposits and withdrawals from single vaults
 */
contract SuperformIntegration {
    using SafeERC20 for IERC20;
    using DataLib for uint256;

    uint256 public maxSlippage = 50; // 0.5%

    ISuperformFactory public superformFactory;
    IBaseRouterImplementation public superformRouter;
    ISuperPositions public superPositions;

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event SuperformSingleVaultDeposit(
        uint256 indexed superformId,
        uint256 assetAmount,
        address indexed receiver,
        address indexed receiverSP,
        uint256 superPositionsReceived
    );

    event SuperformSingleVaultWithdraw(
        uint256 indexed superformId,
        uint256 superPositionAmount,
        address indexed receiver,
        address indexed receiverSP,
        uint256 assetReceived
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error InvalidSuperformId(uint256 superformId);
    error ZeroAmount();
    error ZeroAddress();

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    /**
     * @param superformFactory_ Address of the Superform factory
     * @param superformRouter_ Address of the Superform router
     * @param superPositions_ Address of the Superform positions
     */
    constructor(
        address superformFactory_,
        address superformRouter_,
        address superPositions_
    ) {
        require(superformFactory_ != address(0), ZeroAddress());
        require(superformRouter_ != address(0), ZeroAddress());
        require(superPositions_ != address(0), ZeroAddress());

        superformFactory = ISuperformFactory(superformFactory_);
        superformRouter = IBaseRouterImplementation(superformRouter_);
        superPositions = ISuperPositions(superPositions_);
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /**
     * @notice Deposits assets into a single vault
     * @return superPositionReceived Amount of Superform positions minted
     */
    function singleVaultDeposit(
        uint256 superformId_,
        uint256 assetAmount_,
        address receiver_,
        address receiverSP_
    ) external payable returns (uint256 superPositionReceived) {
        require(superformFactory.isSuperform(superformId_), InvalidSuperformId(superformId_));
        require(receiver_ != address(0), ZeroAddress());
        require(receiverSP_ != address(0), ZeroAddress());
        require(assetAmount_ > 0, ZeroAmount());

        (address superformAddress,,) = superformId_.getSuperform();
        IBaseForm superform = IBaseForm(superformAddress);

        address asset = superform.getVaultAsset();

        // use superform function similar to ERC4626, to determine output amount
        uint256 outputAmount = superform.previewDepositTo(assetAmount_);

        uint256 superPositionsBefore = superPositions.balanceOf(receiverSP_, superformId_);

        superformRouter.singleDirectSingleVaultDeposit(
            _generateReq(
                superformId_,
                assetAmount_,
                outputAmount,
                asset,
                receiver_,
                receiverSP_
            )
        );

        superPositionReceived =
            superPositions.balanceOf(receiverSP_, superformId_) - superPositionsBefore;

        emit SuperformSingleVaultDeposit(
            superformId_,
            assetAmount_,
            receiver_,
            receiverSP_,
            superPositionReceived
        );
    }

    /**
     * @notice Withdraws assets from a single vault
     * @return assetReceived Amount of assets withdrawn from the vault
     */
    function singleVaultWithdraw(
        uint256 superformId_,
        uint256 superPositionAmount_,
        address receiver_,
        address receiverSP_
    ) external payable returns (uint256 assetReceived) {
        require(superformFactory.isSuperform(superformId_), InvalidSuperformId(superformId_));
        require(receiver_ != address(0), ZeroAddress());
        require(receiverSP_ != address(0), ZeroAddress());
        require(superPositionAmount_ > 0, ZeroAmount());

        (address superformAddress,,) = superformId_.getSuperform();
        IBaseForm superform = IBaseForm(superformAddress);

        address asset = superform.getVaultAsset();

        // use superform function similar to ERC4626, to determine output amount
        uint256 outputAmount = superform.previewWithdrawFrom(superPositionAmount_);

        uint256 assetBefore = IERC20(asset).balanceOf(receiverSP_);

        superformRouter.singleDirectSingleVaultDeposit(
            _generateReq(
                superformId_,
                superPositionAmount_,
                outputAmount,
                asset,
                receiver_,
                receiverSP_
            )
        );

        assetReceived = IERC20(asset).balanceOf(receiverSP_) - assetBefore;

        emit SuperformSingleVaultWithdraw(
            superformId_,
            superPositionAmount_,
            receiver_,
            receiverSP_,
            assetReceived
        );
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /**
     * @dev Constructs a request for single vault operations,
     *      a `SingleDirectSingleVaultStateReq` struct
     *
     * @param superformId_ ID of the Superform entity involved in the operation
     * @param amount_ Amount involved in the operation
     * @param outputAmount_ Expected output from the operation
     * @param asset_ Address of the asset used
     * @param receiver_ Address receiving the operation result
     * @param receiverSP_ Address for SuperPositions, if applicable
     * @return req Struct with operation details
     */
    function _generateReq(
        uint256 superformId_,
        uint256 amount_,
        uint256 outputAmount_,
        address asset_,
        address receiver_,
        address receiverSP_
    ) internal view returns (SingleDirectSingleVaultStateReq memory req) {
        req = SingleDirectSingleVaultStateReq ({
            superformData: SingleVaultSFData({
                superformId: superformId_,
                amount: amount_,
                outputAmount: outputAmount_,
                maxSlippage: maxSlippage,
                liqRequest: LiqRequest({
                    txData: bytes(""),
                    token: asset_,
                    interimToken: address(0),
                    bridgeId: 1,
                    liqDstChainId: 0,
                    nativeAmount: 0
                }),
                permit2data: bytes(""),
                hasDstSwap: false,
                retain4626: false,
                receiverAddress: receiver_,
                receiverAddressSP: receiverSP_,
                extraFormData: bytes("")
            })
        });
    }
}
