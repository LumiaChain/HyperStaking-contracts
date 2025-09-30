// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {PirexEth} from "../../../external/pirex/PirexEth.sol";
import {AutoPxEth} from "../../../external/pirex/AutoPxEth.sol";

import {DataTypes} from "../../../external/pirex/libraries/DataTypes.sol";

contract PirexIntegration is Initializable {
    using SafeERC20 for IERC20;

    /// PxEth (ERC20) contract address
    address public PX_ETH;

    /// PirexEth contract address
    address public PIREX_ETH;

    /// AutoPxEth (ERC4626) contract address
    address public AUTO_PX_ETH;

    /// Storage gap for upgradeability. Must remain the last state variable
    uint256[50] private __gap;

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event PirexDepositCompound(
        address indexed receiver,
        uint256 ethDeposited,
        uint256 postFeeAmount,
        uint256 feeAmount,
        uint256 apxEthReceived
    );

    event PirexInstantEthRedeem(
        address indexed receiver,
        uint256 shares,
        uint256 apxEthReceived,
        uint256 ethReceived,
        uint256 feeAmount
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error ZeroAmountPx();
    error ZeroAddressPx();

    //============================================================================================//
    //                                        Initialize                                          //
    //============================================================================================//

    function __PirexIntegration_init(
        address pxEth_,
        address pirexEth_,
        address autoPxEth_
    ) internal onlyInitializing {
        require(pxEth_ != address(0), ZeroAddressPx());
        require(pirexEth_ != address(0), ZeroAddressPx());
        require(autoPxEth_ != address(0), ZeroAddressPx());

        PX_ETH = pxEth_;
        PIREX_ETH = pirexEth_;
        AUTO_PX_ETH = autoPxEth_;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    function depositCompound(address receiver_, uint256 value) public payable returns (uint256 apxEthReceived) {
        require(receiver_ != address(0), ZeroAddressPx());
        require(value > 0, ZeroAmountPx());

        // Retrieve this value before making the compound deposit, as it will alter the vault ratio
        apxEthReceived = _convertEthToApxEth(value);

        bool compound = true;
        (uint256 postFeeAmount, uint256 feeAmount) = PirexEth(PIREX_ETH).deposit{
            value: value
        }(
            receiver_,
            compound
        );

        emit PirexDepositCompound(receiver_, value, postFeeAmount, feeAmount, apxEthReceived);
    }

    // shares - apxEth amount
    function redeem(uint256 shares_, address receiver_) public returns (uint256 ethReceived) {
        require(receiver_ != address(0), ZeroAddressPx());
        require(shares_ > 0, ZeroAmountPx());

        // apxEth -> pxEth
        uint256 pxEthReceived = AutoPxEth(AUTO_PX_ETH).redeem(shares_, address(this), address(this));

        // pxEth -> Eth
        IERC20(PX_ETH).safeIncreaseAllowance(PIREX_ETH, pxEthReceived);
        uint256 feeAmount;
        (ethReceived, feeAmount) = PirexEth(PIREX_ETH).instantRedeemWithPxEth(
            pxEthReceived,
            receiver_
        );

        emit PirexInstantEthRedeem(receiver_, shares_, pxEthReceived, ethReceived, feeAmount);
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    // ========= View ========= //

    /// Return current eth to apxEth ratio (price)
    function _convertEthToApxEth(uint256 amount_) internal view returns (uint256) {
        (uint256 postFeeAmount,) = _computeAssetAmounts(
            DataTypes.Fees.Deposit,
            amount_
        );

        return AutoPxEth(AUTO_PX_ETH).previewDeposit(postFeeAmount);
    }

    /// Return current asset to stake ratio (price)
    function _convertApxEthToEth(uint256 amount_) internal view returns (uint256) {
        uint256 pxEthAmount = AutoPxEth(AUTO_PX_ETH).previewRedeem(amount_);

        (uint256 postFeeAmount,) = _computeAssetAmounts(
            DataTypes.Fees.InstantRedemption,
            pxEthAmount
        );

        return postFeeAmount;
    }

    /**
     * @notice This function calculates the Pirex post-fee asset amount and fee amount based on the
               specified fee type and total assets
     * @dev Source:
     *      https://github.com/dinero-protocol/pirex-eth-contracts/blob/master/src/PirexEth.sol#L545
     *
     * @param f_ representing the fee type
     * @param amount_ Total ETH or pxETH asset amount
     * @return postFeeAmount Post-fee asset amount (for mint/burn/claim/etc.)
     * @return feeAmount Fee amount
     */
    function _computeAssetAmounts(
        DataTypes.Fees f_,
        uint256 amount_
    ) internal view returns (uint256 postFeeAmount, uint256 feeAmount) {
        uint256 denominator = 1_000_000;
        uint32 fee = PirexEth(PIREX_ETH).fees(f_);

        feeAmount = (amount_ * fee) / denominator;
        postFeeAmount = amount_ - feeAmount;
    }
}
