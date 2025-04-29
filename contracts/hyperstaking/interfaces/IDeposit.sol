// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {DirectStakeInfo} from "../libraries/LibHyperStaking.sol";

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

    event StakeWithdraw(
        address from,
        address indexed to,
        address indexed strategy,
        uint256 stake,
        uint256 withdrawAmount,
        DepositType indexed depositType
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

    /// @notice Thrown when depositing to a not direct deposit vault
    error NotDirectDeposit(address strategy);


    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /* ========== Direct Deposit ========== */

    /**
     * @notice Deposits a specified stake amount directly into the lockbox and bridges it to Lumia
     *         Uses a designated Strategy contract, which does not perform any yield strategy generation
     * @param strategy The address of the strategy associated with the vault
     * @param stake The amount of the token to stake
     * @param to The address receiving the staked token allocation (typically the user's address)
     */
    function directStakeDeposit(
        address strategy,
        uint256 stake,
        address to
    ) external payable;

    /**
     * @notice Withdraws a specified stake
     * @dev Used internally and is called by Lockbox after getting StakeRedeem message
     * @param strategy The address of the strategy associated with the vault
     * @param stake The amount of the staked token to withdraw
     * @param to The address to receive the withdrawn tokens
     */
    function directStakeWithdraw(
        address strategy,
        uint256 stake,
        address to
    ) external returns (uint256 withdrawAmount);

    /* ========== Active Deposit  ========== */

    /**
     * @notice Deposits a specified stake amount into chosen strategy
     * @param strategy The address of the strategy selected by the user
     * @param stake The amount of the token to stake
     * @param to The address receiving the staked token allocation (typically the user's address)
     */
    function stakeDeposit(
        address strategy,
        uint256 stake,
        address to
    ) external payable;

    /**
     * @notice Withdraws a specified amount of shares, which are then exchanged for stake
     *         and send to the user
     * @dev Used internally and is called by Lockbox after getting StakeRedeem message
     * @param strategy The address of the strategy associated with the vault
     * @param stake The amount of the staked token to withdraw
     * @param to The address to receive the withdrawn tokens
     */
    function stakeWithdraw(
        address strategy,
        uint256 stake,
        address to
    ) external returns (uint256 withdrawAmount);

    /* ========== */

    /// @notice Pauses stake functionalities
    function pauseDeposit() external;

    /// @notice Resumes stake functionalities
    function unpauseDeposit() external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /// @notice Retrieves information about all direct stakes for a specified strategy
    function directStakeInfo(address strategy) external view returns (DirectStakeInfo memory);
}
