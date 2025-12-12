// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

// solhint-disable func-name-mixedcase

import {Claim} from "../libraries/LibHyperStaking.sol";

/**
 * @title IDeposit
 * @dev Interface for DepositFacet
 */
interface IDeposit {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event StakeDeposit(
        address from,
        address indexed to,
        address indexed strategy,
        uint256 stake
    );

    event WithdrawClaimed(
        address indexed strategy,
        address indexed from,
        address to,
        uint256 stake,
        uint256 exitAmount
    );

    event FeeWithdrawClaimed(
        address indexed strategy,
        address indexed feeRecipient,
        address to,
        uint256 fee,
        uint256 exitAmount
    );

    event WithdrawQueued(
        address indexed strategy,
        address indexed to,
        uint256 requestId,
        uint64 unlockTime,
        uint256 expectedAmount,
        bool indexed feeWithdraw
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

    /// @notice Thrown when attempting to stake to disabled strategy
    error StrategyDisabled(address strategy);

    /// @notice Thrown when attempting to deposit to a non-existent vault
    error VaultDoesNotExist(address strategy);

    /// @notice Thrown when trying to claim still locked stake
    error ClaimTooEarly(uint64 time, uint64 unlockTime);

    /// @notice Thrown when attempting to claim without providing any request IDs
    error EmptyClaim();

    /// @notice Thrown when attempting to claim to the zero address
    error ClaimToZeroAddress();

    /// @notice Thrown when a pending claim with the given ID does not exist
    error ClaimNotFound(uint256 id);

    /// @notice Thrown when the sender is not the eligible address for the claim
    error NotEligible(uint256 id, address eligible, address sender);

    /// @notice Thrown when trying to set too high withdraw delay
    error WithdrawDelayTooHigh(uint64 newDelay);

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /* ========== Deposit  ========== */

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
     * @notice Withdraws stake for the given requests
     * @dev Reverts if any of the requests are not currently claimable
     * @param requestIds IDs of withdrawal requests to claim
     * @param to Recipient address for the withdrawn stake
     */
    function claimWithdraws(uint256[] calldata requestIds, address to) external;

    /**
     * @notice Queues a stake withdrawal
     * @dev Called internally once the cross‑chain `StakeRedeem` message is verified
     *      It **does not** transfer tokens; it just records a pending withdrawal
     *      for the user that becomes available after `withdrawDelay`
     * @param strategy Strategy address that produced the request
     * @param user Address eligible to claim the withdrawal
     * @param stake The amount of stake to withdraw
     * @param allocation The amount of asset allocation in strategy
     * @param feeWithdraw True for protocol-fee withdrawals
     */
    function queueWithdraw(
        address strategy,
        address user,
        uint256 stake,
        uint256 allocation,
        bool feeWithdraw
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

    /// @notice Returns claims for given requestIds; chooses fee/user mapping by flag
    function pendingWithdraws(uint256[] calldata requestIds)
        external
        view
        returns (Claim[] memory claims);

    /// @notice Returns up to `limit` most recent claim IDs for a strategy and user
    /// @dev Newest IDs first
    function lastClaims(address strategy, address user, uint256 limit)
        external
        view
        returns (uint256[] memory ids);
}
