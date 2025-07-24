// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IRealAssets} from "../interfaces/IRealAssets.sol";
import {IStakeRedeemRoute} from "../interfaces/IStakeRedeemRoute.sol";
import {LumiaDiamondAcl} from "../LumiaDiamondAcl.sol";
import {
    LibInterchainFactory, InterchainFactoryStorage, RouteInfo
} from "../libraries/LibInterchainFactory.sol";

import {LumiaPrincipal} from "../tokens/LumiaPrincipal.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {
    HyperlaneMailboxMessages, StakeRedeemData
} from "../../hyperstaking/libraries/HyperlaneMailboxMessages.sol";

/**
 * @title RealAssetsFacet
 * @notice Facet responsible for minting and redeeming RWA (Real-World Asset) tokens
 */
contract RealAssetsFacet is IRealAssets, LumiaDiamondAcl, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using HyperlaneMailboxMessages for bytes;

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Diamond Internal ========= //

    /// @inheritdoc IRealAssets
    function mint(
        bytes calldata data
    ) external diamondInternal nonReentrant {
        address strategy = data.strategy();
        address sender = data.sender();
        uint256 stake = data.stake();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        LibInterchainFactory.checkRoute(ifs, strategy);

        RouteInfo storage r = ifs.routes[strategy];

        // mint principal first
        LumiaPrincipal(address(r.assetToken)).mint(address(this), stake);

        // deposit principal to vault and send shares to sender
        r.assetToken.safeIncreaseAllowance(address(r.vaultShares), stake);
        uint256 shares = r.vaultShares.deposit(stake, sender);

        emit RwaMint(strategy, sender, stake, shares);
    }

    /// @inheritdoc IRealAssets
    function stakeReward(
        bytes calldata data
    ) external diamondInternal nonReentrant {
        address strategy = data.strategy();
        uint256 stakeAdded = data.stakeAdded();

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();
        LibInterchainFactory.checkRoute(ifs, strategy);

        RouteInfo storage r = ifs.routes[strategy];

        // mint additional principal
        LumiaPrincipal(address(r.assetToken)).mint(address(this), stakeAdded);

        // increase principal reserve in vault, increase shares ratio, without minting new shares
        r.assetToken.safeTransfer(address(r.vaultShares), stakeAdded);

        emit RwaStakeReward(strategy, stakeAdded);
    }

    /// @inheritdoc IRealAssets
    function redeem(
        address strategy,
        address from,
        address to,
        uint256 shares
    ) external payable nonReentrant {
        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        LibInterchainFactory.checkRoute(ifs, strategy);

        RouteInfo storage r = ifs.routes[strategy];

        if (from != msg.sender) {
            r.vaultShares.spendAllowance(from, msg.sender, shares);
        }

        // redeem shares `from` to this contract (require user allowance to burn shares)
        uint256 assets = r.vaultShares.redeem(shares, address(this), from);

        // burn assets, so they can be unlocked on the origin chain
        LumiaPrincipal(address(r.assetToken)).burnFrom(address(r.vaultShares), assets);

        // use hyperlane handler function for dispatching stake redeem msg
        StakeRedeemData memory data = StakeRedeemData({
            strategy: strategy,
            sender: to,
            redeemAmount: assets
        });
        IStakeRedeemRoute(address(this)).stakeRedeemDispatch{value: msg.value}(data);

        emit RwaRedeem(strategy, from, to, assets, shares);
    }

}
