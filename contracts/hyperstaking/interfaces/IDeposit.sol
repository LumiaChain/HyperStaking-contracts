// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

// solhint-disable func-name-mixedcase

import {DirectStakeInfo} from "../libraries/LibHyperStaking.sol";
import {VaultInfo} from "../libraries/LibHyperStaking.sol";

/**
 * @title IDeposit
 * @dev Interface for DepositFacet
 */
interface IDeposit {
    enum DepositType {
        Direct,
        Active
    }

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event StakeDeposit(
        address from,
        address indexed to,
        address indexed strategy,
        uint256 stake,
        DepositType indexed depositType     // 0 - Direct
                                            // 1 - Active
    );

    event WithdrawClaimed(
        address indexed strategy,
        address indexed to,
        uint256 stake,
        DepositType indexed depositType
    );

    event WithdrawQueued(
        address indexed strategy,
        address indexed to,
        uint256 stake,
        uint64 unlockTime
    );

    event FeeWithdraw(
        address indexed feeRecipient,
        address indexed strategy,
        uint256 fee
    );

    event WithdrawDelaySet(
        address indexed stakingManager,
        uint256 previousDelay,
        uint256 newDelay
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    /// @notice Thrown when attempting to stake zero amount
    error ZeroStake();

    /// @notice Thrown when attempting to claim zero amount
    error ZeroClaim();

    /// @notice Thrown when attempting to stake to disabled strategy
    error StrategyDisabled(address strategy);

    /// @notice Thrown when attempting to deposit to a non-existent vault
    error VaultDoesNotExist(address strategy);

    /// @notice Thrown when depositing to a not direct deposit vault
    error NotDirectDeposit(address strategy);

    /// @notice Thrown when trying to claim still locked stake
    error ClaimTooEarly(uint64 time, uint64 unlockTime);

    /// @notice Thrown when trying to set too high withdraw delay
    error WithdrawDelayTooHigh(uint64 newDelay);

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /* ========== Direct Deposit ========== */

    /**
     * @notice Deposits a specified stake amount directly into the lockbox and bridges it to Lumia
     *         Uses a designated Strategy contract, which does not perform any yield strategy generation
     * @param strategy The address of the strategy associated with the vault
     * @param to The address receiving the staked token allocation (typically the user's address)
     * @param stake The amount of the token to stake
     */
    function directStakeDeposit(
        address strategy,
        address to,
        uint256 stake
    ) external payable;

    /* ========== Active Deposit  ========== */

    /**
     * @notice Deposits a specified stake amount into chosen strategy
     * @param strategy The address of the strategy selected by the user
     * @param to The address receiving the staked token allocation (typically the user's address)
     * @param stake The amount of the token to stake
     */
    function stakeDeposit(
        address strategy,
        address to,
        uint256 stake
    ) external payable;

    /* ========== Stake Withdraw  ========== */

    /**
     * @notice Withdraws all tokens whose claim‑delay has elapsed
     * @dev Reverts if nothing is yet claimable
     * @param strategy The address of the strategy
     * @param to Claim recipient address
     */
    function claimWithdraw(address strategy, address to) external;

    /**
     * @notice Queues a stake withdrawal and starts the claim‐delay timer
     * @dev Called internally once the cross‑chain `StakeRedeem` message is verified
     *      It **does not** transfer tokens; it just records a pending withdrawal
     *      for the user that becomes available after `withdrawDelay`
     * @param strategy Address of the strategy
     * @param to Address that will be able to claim the tokens
     * @param stake Amount of the currecy to queue for claim
     */
    function queueWithdraw(
        address strategy,
        address to,
        uint256 stake
    ) external;

    /**
     * @notice Withdraws protocol fee
     * @dev Used internally after report with non-zero feeRate
     * @param vault VaultInfo of the strategy
     * @param feeRecipient The address of fee recipient
     * @param fee The amount of fee to withdraw
     */
    function feeWithdraw(
        VaultInfo calldata vault,
        address feeRecipient,
        uint256 fee
    ) external;

    /* ========== */

    /**
     * @notice Sets the global delay between queuing and withdrawing
     * @dev Only callable by the Staking Manger role
     * @param newDelay Delay in seconds (e.g. 2 days → 172_800)
     */
    function setWithdrawDelay(uint64 newDelay) external;

    /// @notice Pauses stake functionalities
    function pauseDeposit() external;

    /// @notice Resumes stake functionalities
    function unpauseDeposit() external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice public constant, but it is nice to make interface for Diamond
    function MAX_WITHDRAW_DELAY() external view returns(uint64);

    /// @notice Cool‑down in seconds that must elapse before a queued claim can be withdrawn
    function withdrawDelay() external view returns (uint64);

    /**
     * @notice Returns the user’s queued‑but‑not‑yet‑withdrawable amount
     * @param user Address to query
     * @return amount Amount of currency that will become withdrawable
     * @return unlockTime Timestamp, after which `claimWithdraw` succeeds
     */
    function pendingWithdraw(
        address user,
        address strategy
    ) external view returns (uint256 amount, uint256 unlockTime);

    /// @notice Retrieves information about all direct stakes for a specified strategy
    function directStakeInfo(address strategy) external view returns (DirectStakeInfo memory);
}
