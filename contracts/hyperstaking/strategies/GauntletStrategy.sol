// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {StrategyKind, StrategyRequest, IStrategy} from "../interfaces/IStrategy.sol";
import {AbstractStrategy} from "./AbstractStrategy.sol";
import {LumiaGtUSDaAllocation} from "./tokens/LumiaGtUSDaAllocation.sol";
import {Currency} from "../libraries/CurrencyHandler.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Provisioner} from "../../external/aera/Provisioner.sol";
import {RequestType} from "../../external/aera/Types.sol";
import {IPriceAndFeeCalculator} from "../../external/aera/interfaces/IPriceAndFeeCalculator.sol";

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
    LumiaGtUSDaAllocation public immutable LUMIA_GTUSDA;

    /// @notice Stake token accepted by the strategy (input currency)
    IERC20 public immutable STAKE_TOKEN;

    /// @notice Aera Provisioner used to submit deposit and redeem requests
    Provisioner public immutable AERA_PROVISIONER;

    /// @notice The price calculator contract taken from aera provisioner
    IPriceAndFeeCalculator public immutable AERA_PRICE;

    /// @notice The vault contract taken from aera provisioner (actial gtUSDa)
    address public immutable AERA_VAULT;

    /// @dev slippage in basis points (1 bp = 0.01 %)
    uint256 public slippageBps;

    /// @notice Guaranteed allocation amounts per requestId
    /// @dev Stores the minimum allocation units that will be minted when the request is claimed
    mapping(uint256 requestId => uint256 minUnitsOut) public pendingAllocation;

    /// @notice Guaranteed stake-out per exit request
    /// @dev Equal to minTokensOut passed to Aera for this request
    mapping(uint256 requestId => uint256 minStakeOut) public pendingExit;

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event AeraConfigUpdated(AeraConfig newConfig);
    event AeraAsyncDepositHash(bytes32 requestHash);
    event AeraAsyncRedeemHash(bytes32 requestHash);

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

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    constructor(
        address diamond_,
        address stakeToken_, // (gtUSDa uses USDC as deposit, in time of writting..)
        address aeraProvisioner_
    ) AbstractStrategy(diamond_) {
        // deploys new ERC20 token owned by this strategy
        LUMIA_GTUSDA = new LumiaGtUSDaAllocation();

        STAKE_TOKEN = IERC20(stakeToken_);
        AERA_PROVISIONER = Provisioner(aeraProvisioner_);
        AERA_PRICE = AERA_PROVISIONER.PRICE_FEE_CALCULATOR();
        AERA_VAULT = AERA_PROVISIONER.MULTI_DEPOSITOR_VAULT();

        // recommended values from aera docs:
        // https://docs.aera.finance/integrating-with-gtusda
        aeraConfig = AeraConfig({
            solverTip: 0,
            deadlineOffset: 3 days,
            maxPriceAge: 3600,
            isFixedPrice: false,
            slippageBps: 300 /// 3%
        });

        ( // check if area impl have async operations enabled
            bool asyncDepositEnabled, bool asyncRedeemEnabled, , ,
        ) = AERA_PROVISIONER.tokensDetails(STAKE_TOKEN);

        require(asyncDepositEnabled, AeraDepositDisabled());
        require(asyncRedeemEnabled, AeraRedeemDisabled());
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
        pendingAllocation[requestId_] = minUnitsOut;

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
        pendingExit[requestId_] = minTokensOut;

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

    // ========= View ========= //

    /// @notice Update Aera integration config
    /// @param newConfig New config, with slippageBps in basis points (10_000 = 100%)
    function setAeraConfig(AeraConfig calldata newConfig) external onlyStrategyManager {
        if (newConfig.slippageBps > 10_000) revert InvalidConfig();
        aeraConfig = newConfig;
        emit AeraConfigUpdated(newConfig);
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
        allocation = pendingAllocation[id_];
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
        exitAmount = pendingExit[id_];
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
        return (expected * (10_000 - slippageBps)) / 10_000;
    }

    /// @dev Returns a conservative preview of tokens for a given allocation
    function _previewExitRaw(uint256 allocation_) internal view override returns (uint256) {
        uint256 expected = AERA_PRICE.convertUnitsToToken(AERA_VAULT, STAKE_TOKEN, allocation_);
        return (expected * (10_000 - slippageBps)) / 10_000;
    }

    /// @dev Returns execution deadline by adding the configured offset to the current block time
    function _aeraDeadline() internal view returns (uint256) {
        return block.timestamp + aeraConfig.deadlineOffset;
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
