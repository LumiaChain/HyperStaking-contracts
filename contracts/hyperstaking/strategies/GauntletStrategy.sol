// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

// solhint-disable var-name-mixedcase

import {StrategyKind, StrategyRequest, IStrategy} from "../interfaces/IStrategy.sol";
import {IHyperFactory} from "../interfaces/IHyperFactory.sol";
import {AbstractStrategy} from "./AbstractStrategy.sol";
import {LumiaGtUSDa} from "./tokens/LumiaGtUSDa.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Provisioner} from "../../external/aera/Provisioner.sol";
import {RequestType} from "../../external/aera/Types.sol";
import {IPriceAndFeeCalculator} from "../../external/aera/interfaces/IPriceAndFeeCalculator.sol";

import {Currency} from "../../shared/libraries/CurrencyHandler.sol";

// @notice Config for Aera Provisioner deposit/redeem calls
struct AeraConfig {
    uint256 solverTip;
    uint256 deadlineOffset;
    uint256 maxPriceAge;
    uint256 slippageBps;
    bool isFixedPrice;
}

/**
 * @title GauntletStrategy
 * @notice HyperStaking strategy using Aera + Gauntlet gtUSDa as yield position
 */
contract GauntletStrategy is AbstractStrategy {
    using SafeERC20 for IERC20;

    /// @notice Current Aera config
    AeraConfig public aeraConfig;

    /// @notice Address of the Gauntlet derived token, used as allocation for the HyperStaking
    LumiaGtUSDa public LUMIA_GTUSDA;

    /// @notice Stake token accepted by the strategy (input currency)
    IERC20 public STAKE_TOKEN;

    /// @notice Aera Provisioner used to submit deposit and redeem requests
    Provisioner public AERA_PROVISIONER;

    /// @notice The price calculator contract taken from aera provisioner
    IPriceAndFeeCalculator public AERA_PRICE;

    /// @notice The vault contract taken from aera provisioner (actual gtUSDa)
    address public AERA_VAULT;

    /// @notice Recorded allocation amounts per requestId
    /// @dev Stores the minimum allocation units that were guaranteed when the request was created
    mapping(uint256 requestId => uint256 minUnitsOut) public recordedAllocation;

    /// @notice Recorded stake-out per exit request
    /// @dev Equal to the minTokensOut passed to Aera for this request preserved as a record
    mapping(uint256 requestId => uint256 minStakeOut) public recordedExit;

    /// @notice Keeps the last used deadline for Aera requests
    uint256 private _lastAeraDeadline;

    /// Storage gap for upgradeability. Must remain the last state variable
    uint256[50] private __gap;

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event AeraConfigUpdated(AeraConfig newConfig);
    event AeraAsyncDepositHash(bytes32 requestHash);
    event AeraAsyncRedeemHash(bytes32 requestHash);

    event StakeTokenUpdated(address oldStakeToken, address newStakeToken);

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error AeraDepositDisabled();
    error AeraRedeemDisabled();

    error ZeroReceiver();
    error PendingAllocationMissing();
    error PendingExitMissing();
    error MissingLiquidity();

    error SlippageTooHigh();
    error InvalidConfig();

    error StakeTokenAlreadySet();

    //============================================================================================//
    //                                        Initialize                                          //
    //============================================================================================//

    function initialize (
        address diamond_,
        address stakeToken_, // (gtUSDa uses USDC as deposit, in time of writing)
        address aeraProvisioner_
    ) public initializer {
        __AbstractStrategy_init(diamond_);

        require(stakeToken_ != address(0), ZeroAddress());

        // deploys new ERC20 token owned by this strategy
        LUMIA_GTUSDA = new LumiaGtUSDa();

        STAKE_TOKEN = IERC20(stakeToken_);
        AERA_PROVISIONER = Provisioner(aeraProvisioner_);
        AERA_PRICE = AERA_PROVISIONER.PRICE_FEE_CALCULATOR();
        AERA_VAULT = AERA_PROVISIONER.MULTI_DEPOSITOR_VAULT();

        // recommended values from aera docs:
        // https://docs.aera.finance/integrating-with-gtusda
        aeraConfig = AeraConfig({
            solverTip: 0,
            deadlineOffset: 2 days,
            maxPriceAge: 3600,
            isFixedPrice: false,
            slippageBps: 100 /// 1%
        });

        // check if Area impl have async operations enabled
        _verifyStakeToken(stakeToken_);
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Diamond ========= //

    /// @inheritdoc IStrategy
    function requestAllocation(
        uint256 requestId_,
        uint256 amount_,
        address user_
    ) public payable virtual onlyLumiaDiamond returns (uint64 readyAt) {
        require(user_ != address(0), ZeroUser());
        require(amount_ != 0, ZeroAmount());

        readyAt = 0; // claimable immediately, thanks to wrapper token
        _storeAllocationRequest(
            requestId_,
            user_,
            amount_,
            readyAt
        );

        // compute minimum allocation area guarantees
        uint256 minUnitsOut = _previewAllocationRaw(amount_);

        // save minUnitsOut for later claim settlement
        recordedAllocation[requestId_] = minUnitsOut;

        // transfer stake amount to this contract and approve Aera
        STAKE_TOKEN.safeTransferFrom(msg.sender, address(this), amount_);
        STAKE_TOKEN.safeIncreaseAllowance(address(AERA_PROVISIONER), amount_);

        uint256 deadline = _aeraDeadline();

        // actual deposit request
        AERA_PROVISIONER.requestDeposit(
            STAKE_TOKEN,
            amount_,
            minUnitsOut,
            aeraConfig.solverTip,
            deadline,
            aeraConfig.maxPriceAge,
            aeraConfig.isFixedPrice
        );

        // emit additional aera-related info about the request
        RequestType requestType = aeraConfig.isFixedPrice ? RequestType.DEPOSIT_FIXED_PRICE : RequestType.DEPOSIT_AUTO_PRICE;
        emit AeraAsyncDepositHash(_getRequestHashParams(
            STAKE_TOKEN,
            address(this),
            requestType,
            amount_,
            minUnitsOut,
            aeraConfig.solverTip,
            deadline,
            aeraConfig.maxPriceAge
        ));

        emit AllocationRequested(requestId_, user_, amount_, readyAt);
    }

    /// @inheritdoc IStrategy
    function claimAllocation(
        uint256[] calldata ids_,
        address receiver_
    ) public virtual onlyLumiaDiamond returns (uint256 allocation) {
        require(receiver_ != address(0), ZeroReceiver());

        uint256 n = ids_.length;
        for (uint256 i; i < n; ++i) {
            allocation += _claimOneAllocation(ids_[i], receiver_);
        }
    }

    /// @inheritdoc IStrategy
    function requestExit(
        uint256 requestId_,
        uint256 shares_,
        address user_
    ) public virtual onlyLumiaDiamond returns (uint64 readyAt) {
        require(user_ != address(0), ZeroUser());
        require(shares_ != 0, ZeroAmount());

        uint256 deadline = _aeraDeadline();
        readyAt = uint64(deadline);

        _storeExitRequest(
            requestId_,
            user_,
            shares_,
            readyAt
        );

        // compute conservative minimum stake the strategy guarantees
        uint256 minTokensOut = _previewExitRaw(shares_);

        // guaranteed minimum units for this request
        recordedExit[requestId_] = minTokensOut;

        // transfer stake amount to this contract and approve Aera
        IERC20(address(LUMIA_GTUSDA)).safeTransferFrom(msg.sender, address(this), shares_);

        IERC20(AERA_VAULT).safeIncreaseAllowance(address(AERA_PROVISIONER), shares_);

        // actual deposit request
        AERA_PROVISIONER.requestRedeem(
            STAKE_TOKEN,
            shares_,
            minTokensOut,
            aeraConfig.solverTip,
            deadline,
            aeraConfig.maxPriceAge,
            aeraConfig.isFixedPrice
        );

        // emit additional aera-related info about the request
        RequestType requestType = aeraConfig.isFixedPrice ? RequestType.REDEEM_FIXED_PRICE : RequestType.REDEEM_AUTO_PRICE;

        emit AeraAsyncRedeemHash(_getRequestHashParams(
            STAKE_TOKEN,
            address(this),
            requestType,
            minTokensOut,
            shares_,
            aeraConfig.solverTip,
            deadline,
            aeraConfig.maxPriceAge
        ));

        emit ExitRequested(requestId_, user_, shares_, readyAt);
    }

    /// @inheritdoc IStrategy
    function claimExit(
        uint256[] calldata ids_,
        address receiver_
    ) public virtual onlyLumiaDiamond returns (uint256 exitAmount) {
        require(receiver_ != address(0), ZeroReceiver());

        uint256 n = ids_.length;
        for (uint256 i; i < n; ++i) {
            exitAmount += _claimOneExit(ids_[i], receiver_);
        }
    }

    /// @notice Update the stake token used by this strategy
    /// @dev Emergency-only: needed when Aera removes a previously supported token
    /// @param newStakeToken_ The new stake token address
    function setStakeToken(address newStakeToken_) external onlyStrategyManager {
        require(newStakeToken_ != address(0), ZeroAddress());
        require(newStakeToken_ != address(STAKE_TOKEN), StakeTokenAlreadySet());

        // checks if Aera supports token
        _verifyStakeToken(newStakeToken_);

        address oldStakeToken = address(STAKE_TOKEN);
        STAKE_TOKEN = IERC20(newStakeToken_);

        IHyperFactory(DIAMOND).updateVaultStakeCurrency(
            address(this),
            Currency({ token: newStakeToken_ })
        );

        emit StakeTokenUpdated(oldStakeToken, newStakeToken_);
    }

    // ========= View ========= //

    /// @notice Update Aera integration config
    /// @param newConfig_ New config, with slippageBps in basis points (10_000 = 100%)
    function setAeraConfig(AeraConfig calldata newConfig_) external onlyStrategyManager {
        if (newConfig_.slippageBps > 10_000) revert InvalidConfig();
        aeraConfig = newConfig_;
        emit AeraConfigUpdated(newConfig_);
    }

    /// @inheritdoc IStrategy
    function stakeCurrency() public view virtual returns(Currency memory) {
        return Currency({
            token: address(STAKE_TOKEN)
        });
    }

    /// @inheritdoc IStrategy
    function revenueAsset() public view virtual returns(address) {
        return address(LUMIA_GTUSDA);
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    /// @notice Claims one allocation request
    function _claimOneAllocation(
        uint256 id_,
        address receiver_
    ) internal returns (uint256 allocation) {
        // check not claimed / ready / correct kind
        _loadClaimable(id_, StrategyKind.Allocation);

        // guaranteed units for this request
        allocation = recordedAllocation[id_];
        require(allocation != 0, PendingAllocationMissing());

        // mark request as claimed
        _markClaimed(id_);

        // mint derivative allocation tokens
        LUMIA_GTUSDA.mint(receiver_, allocation);

        emit AllocationClaimed(id_, receiver_, allocation);
    }

    /// @notice Claims one exit request
    function _claimOneExit(
        uint256 id_,
        address receiver_
    ) internal returns (uint256 exitAmount) {
        // check if already claimed, wrong kind, or not ready
        StrategyRequest memory r = _loadClaimable(id_, StrategyKind.Exit);

        // guaranteed units for this request
        exitAmount = recordedExit[id_];
        require(exitAmount != 0, PendingExitMissing());

        // burn wrapper shares - prevent double spend
        LUMIA_GTUSDA.burn(r.amount);

        // mark request as claimed and clear pending record
        _markClaimed(id_);

        // transfer stake to receiver; revert if contract lacks liquidity
        require(STAKE_TOKEN.balanceOf(address(this)) >= exitAmount, MissingLiquidity());
        STAKE_TOKEN.safeTransfer(receiver_, exitAmount);

        emit ExitClaimed(id_, receiver_, exitAmount);
    }

    // ========= View ========= //

    /// @dev Returns a conservative preview of allocation units for a given stake
    function _previewAllocationRaw(uint256 amount_) internal view override returns (uint256) {
        uint256 expected = AERA_PRICE.convertTokenToUnits(AERA_VAULT, STAKE_TOKEN, amount_);
        return (expected * (10_000 - aeraConfig.slippageBps)) / 10_000;
    }

    /// @dev Returns a conservative preview of tokens for a given allocation
    function _previewExitRaw(uint256 allocation_) internal view override returns (uint256) {
        uint256 expected = AERA_PRICE.convertUnitsToToken(AERA_VAULT, STAKE_TOKEN, allocation_);
        return (expected * (10_000 - aeraConfig.slippageBps)) / 10_000;
    }

    /// @dev Verify the token is supported by Aera with async operations enabled
    function _verifyStakeToken(address stakeToken_) internal view {
        (
            bool asyncDepositEnabled,
            bool asyncRedeemEnabled,
            , ,
        ) = AERA_PROVISIONER.tokensDetails(IERC20(stakeToken_));

        require(asyncDepositEnabled, AeraDepositDisabled());
        require(asyncRedeemEnabled, AeraRedeemDisabled());
    }

    /// @dev Returns execution deadline by adding the configured offset to the current block time
    ///      If multiple requests are made in the same block, bumps by +1 to keep uniqueness
    function _aeraDeadline() internal returns (uint256 deadline) {
        deadline = block.timestamp + aeraConfig.deadlineOffset;

        // ensure strict monotonic increase to avoid hash collisions
        if (deadline <= _lastAeraDeadline) {
            deadline = _lastAeraDeadline + 1;
        }

        _lastAeraDeadline = deadline;
    }

    /// @notice Calculate the request hash in the same way as in the Area Provisioner contract
    /// @dev Look at Provisioner _getRequestHashParams
    function _getRequestHashParams(
        IERC20 token,
        address user,
        RequestType requestType,
        uint256 tokens,
        uint256 units,
        uint256 solverTip,
        uint256 deadline,
        uint256 maxPriceAge
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token, user, requestType, tokens, units, solverTip, deadline, maxPriceAge));
    }
}
