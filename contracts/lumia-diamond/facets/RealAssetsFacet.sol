// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRealAssets} from "../interfaces/IRealAssets.sol";
import {IHyperlaneHandler} from "../interfaces/IHyperlaneHandler.sol";
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
} from "../../shared/libraries/HyperlaneMailboxMessages.sol";
import {LibHyperlaneReplayGuard} from "../../shared/libraries/LibHyperlaneReplayGuard.sol";

import {ZeroAddress, ZeroAmount, RewardDonationZeroSupply } from "../../shared/Errors.sol";

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

        // block donation if the vault has no outstanding shares
        require(r.vaultShares.totalSupply() > 0, RewardDonationZeroSupply());

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
        require(strategy != address(0) && from != address(0) && to != address(0), ZeroAddress());
        require(shares > 0, ZeroAmount());

        InterchainFactoryStorage storage ifs = LibInterchainFactory.diamondStorage();

        LibInterchainFactory.checkRoute(ifs, strategy);

        RouteInfo storage r = ifs.routes[strategy];

        // redeem shares from `from` into this contract using the explicit `caller`
        // when caller != from an allowance from `from` to `caller` is required to burn the shares
        uint256 assets = r.vaultShares.diamondRedeem(shares, msg.sender, address(this), from);

        // burn assets, so they can be unlocked on the origin chain
        LumiaPrincipal(address(r.assetToken)).burnFrom(address(r.vaultShares), assets);

        // quote message fee for forwarding a message across chains
        uint256 dispatchFee = quoteRedeem(strategy, to, shares);
        IHyperlaneHandler(address(this)).collectDispatchFee{value: msg.value}(msg.sender, dispatchFee);

        // use hyperlane handler function for dispatching stake redeem msg
        IHyperlaneHandler(address(this)).bridgeStakeRedeem(
            strategy,
            to,
            assets,
            dispatchFee
        );

        emit RwaRedeem(strategy, from, to, assets, shares);
    }

    // ========= View ========= //

    /// @inheritdoc IRealAssets
    function quoteRedeem(
        address strategy,
        address to,
        uint256 shares
    ) public view returns (uint256) {
        RouteInfo storage r = LibInterchainFactory.diamondStorage().routes[strategy];

        uint256 assets = r.vaultShares.previewRedeem(shares);

        StakeRedeemData memory dispatchData = StakeRedeemData({
            nonce: LibHyperlaneReplayGuard.previewNonce(),
            strategy: strategy,
            sender: to,
            redeemAmount: assets
        });
        return IStakeRedeemRoute(address(this)).quoteDispatchStakeRedeem(dispatchData);
    }
}
