// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20, ERC20, ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {ITier2Vault} from "./interfaces/ITier2Vault.sol";

/**
 * @title VaultToken
 * @notice Base ERC4626 LP Token used in Tier2
 * @dev Mint carried out by Diamond Vault
 */
contract VaultToken is ERC4626, Ownable2Step {
    using SafeERC20 for IERC20;

    /// Lumia Diamond Proxy address
    address public immutable DIAMOND;

    /// Associated with this token Lumia strategy
    address public immutable STRATEGY;

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
        address strategy_,
        IERC20 asset_,
        string memory sharesName,
        string memory sharesSymbol
    ) ERC4626(asset_) ERC20(sharesSymbol, sharesName) Ownable(diamond_) {
        DIAMOND = diamond_;
        STRATEGY = strategy_;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    /** @dev See {IERC4626-deposit}. */
    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override onlyOwner returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /** @dev See {IERC4626-mint}.
     *
     * As opposed to {deposit}, minting is allowed even if the vault is in a state where the price
     * of a share is zero. In this case, the shares will be minted without requiring any assets to
     * be deposited.
     */
    function mint(
        uint256 shares,
        address receiver
    ) public virtual override onlyOwner returns (uint256) {
        return super.mint(shares, receiver);
    }

    /** @dev See {IERC4626-withdraw}. */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        // return shares;
        return super.withdraw(assets, receiver, owner);
    }

    /** @dev See {IERC4626-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256 asserts) {
        // return assets;
        return super.redeem(shares, receiver, owner);
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /**
     * @dev Override withdraw/redeem common workflow, and replace sending underlying assets directly
     *      to the receiver, instead of that approve vault to execute further lumia strategy logic
     *      which will eventually send receiver the associated with this strategy initial stake deposit
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);

        { // -- actual override change

            // get underlying asset address and approve for Diamond
            IERC20(asset()).safeIncreaseAllowance(DIAMOND, assets);

            // execute Tier2 leave path
            ITier2Vault(DIAMOND).leaveTier2(
                STRATEGY,
                receiver,
                assets
            );

        } // --

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
