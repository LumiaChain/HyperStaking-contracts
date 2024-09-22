// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PirexEth} from "../../external/pirex/PirexEth.sol";
import {AutoPxEth} from "../../external/pirex/AutoPxEth.sol";

contract PirexIntegration {
    using SafeERC20 for IERC20;

    /// PxEth (ERC20) contract address
    address public immutable PX_ETH;

    /// PirexEth contract address
    address public immutable PIREX_ETH;

    /// AutoPxEth (ERC4626) contract address
    address public immutable AUTO_PX_ETH;

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event PirexDepositCompound(
        address indexed receiver,
        uint256 ethDeposited,
        uint256 apxEthReceived,
        uint256 feeAmount
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

    error ZeroAmount();

    error ZeroAddress();

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    constructor(
        address pxEth_,
        address pirexEth_,
        address autoPxEth_
    ) {
        require(pxEth_ != address(0), ZeroAddress());
        require(pirexEth_ != address(0), ZeroAddress());
        require(autoPxEth_ != address(0), ZeroAddress());

        PX_ETH = pxEth_;
        PIREX_ETH = pirexEth_;
        AUTO_PX_ETH = autoPxEth_;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    function depositCompound(address receiver_) public payable returns (uint256 apxEthReceived) {
        require(receiver_ != address(0), ZeroAddress());
        require(msg.value > 0, ZeroAmount());

        bool compound = true;
        uint256 feeAmount;
        (apxEthReceived, feeAmount) = PirexEth(PIREX_ETH).deposit{
            value: msg.value
        }(
            receiver_,
            compound
        );

        emit PirexDepositCompound(receiver_, msg.value, apxEthReceived, feeAmount);
    }

    // shares - apxEth amount
    function redeem(uint256 shares_, address receiver_) public returns (uint256 ethReceived) {
        require(receiver_ != address(0), ZeroAddress());
        require(shares_ > 0, ZeroAmount());

        // apxEth -> pxEth
        uint256 pxEthReceived = AutoPxEth(AUTO_PX_ETH).redeem(shares_, address(this), address(this));

        IERC20(PX_ETH).safeIncreaseAllowance(PIREX_ETH, pxEthReceived);

        // pxEth -> Eth
        uint256 feeAmount;
        (ethReceived, feeAmount) = PirexEth(PIREX_ETH).instantRedeemWithPxEth(
            pxEthReceived,
            receiver_
        );

        emit PirexInstantEthRedeem(receiver_, shares_, pxEthReceived, ethReceived, feeAmount);
    }
}
