// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PirexEth} from "../../external/pirex/PirexEth.sol";
import {AutoPxEth} from "../../external/pirex/AutoPxEth.sol";

contract PirexIntegration is Ownable {
    using SafeERC20 for IERC20;

    /// Diamond deployment address
    address public immutable DIAMOND;

    /// PxEth (ERC20) contract address
    address public immutable PX_ETH;

    /// PirexEth contract address
    address public immutable PIREX_ETH;

    /// AutoPxEth (ERC4626) contract address
    address public immutable AUTO_PX_ETH;

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event DepositCompound(
        address indexed user,
        uint256 ethDeposited,
        uint256 apxEthReceived,
        uint256 feeAmount
    );

    event InstantEthRedeem(
        address indexed user,
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

    error BadDepositValue();

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    constructor(
        address owner_,
        address diamond_,
        address pxEth_,
        address pirexEth_,
        address autoPxEth_
    ) Ownable(owner_) {
        require(diamond_ != address(0), ZeroAddress());
        require(pxEth_ != address(0), ZeroAddress());
        require(pirexEth_ != address(0), ZeroAddress());
        require(autoPxEth_ != address(0), ZeroAddress());

        DIAMOND = diamond_;
        PX_ETH = pxEth_;
        PIREX_ETH = pirexEth_;
        AUTO_PX_ETH = autoPxEth_;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    function depositCompound(
        address user_,
        uint256 ethValue_
    ) external payable returns (uint256 apxEthReceived) {
        require(user_ != address(0), ZeroAddress());
        require(ethValue_ > 0, ZeroAmount());
        require(ethValue_ == msg.value, BadDepositValue());

        bool compound = true;
        uint256 feeAmount;
        (apxEthReceived, feeAmount) = PirexEth(PIREX_ETH).deposit{
            value: msg.value
        }(
            DIAMOND, // mint for the Diamond - Staking Vault
            compound
        );

        emit DepositCompound(user_, ethValue_, apxEthReceived, feeAmount);
    }

    // shares - apxEth amount
    function redeem(address user_, uint256 shares_) external returns (uint256 ethReceived) {
        require(user_ != address(0), ZeroAddress());
        require(shares_ > 0, ZeroAmount());

        // apxEth -> pxEth
        uint256 pxEthReceived = AutoPxEth(AUTO_PX_ETH).redeem(shares_, address(this), DIAMOND);

        IERC20(PX_ETH).safeApprove(PIREX_ETH, pxEthReceived);

        // pxEth -> Eth
        uint256 feeAmount;
        (ethReceived, feeAmount) = PirexEth(PIREX_ETH).instantRedeemWithPxEth(
            pxEthReceived,
            DIAMOND
        );

        emit InstantEthRedeem(user_, shares_, pxEthReceived, ethReceived, feeAmount);
    }
}
