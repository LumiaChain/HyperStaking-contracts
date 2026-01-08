// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Currency} from "../../shared/libraries/CurrencyHandler.sol";

enum StrategyKind { Allocation, Exit }

/// @notice Shared request format for both allocation and exit operations in a strategy
struct StrategyRequest {
    address user;       // user associated with the request
    StrategyKind kind;  // Allocation or Exit
    bool claimed;       // set true at claim time
    uint256 amount;     // stake for allocation; shares for exit
    uint64 readyAt;     // 0 => claimable immediately
}

/**
 * @title IStrategy
 * @notice Interface for allocation strategies used within the protocol
 *         Defines standard functions for managing async/sync allocation and exit flow of revenue assets
 */
interface IStrategy {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    /// @notice Emitted when a deposit request is created
    event AllocationRequested(
        uint256 indexed id,
        address indexed user,
        uint256 stakeAmount,
        uint64 readyAt
    );

    /// @notice Emitted when a deposit request is claimed (stake -> shares)
    event AllocationClaimed(
        uint256 indexed id,
        address receiver,
        uint256 assetAllocation
    );

    /// @notice Emitted when an exit request is created
    event ExitRequested(
        uint256 indexed id,
        address indexed user,
        uint256 assetAllocation,
        uint64 readyAt
    );

    /// @notice Emitted when an exit request is claimed (shares -> stake)
    event ExitClaimed(
        uint256 indexed id,
        address receiver,
        uint256 exitStakeAmount
    );

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Enqueues a deposit of stake currency into the strategy
     * @dev If `readyAt` is 0, the request can be claimed immediately (sync deposit)
     * @param requestId_ Unique request ID generated outside the strategy
     * @param stakeAmount_ Amount of stake currency to deposit
     * @param user_ The address of the user making the allocation
     * @return readyAt Earliest timestamp when the request can be claimed (0 = now)
     */
    function requestAllocation(uint256 requestId_, uint256 stakeAmount_, address user_)
        external
        payable
        returns (uint64 readyAt);

    /**
     * @notice Claims one or more allocation requests after they become claimable
     * @param ids_ Array of request IDs to claim
     * @param receiver_ The address that will receive allocation (shares)
     * @return totalAssetAllocation Total number of shares allocated across all claimed requests
     */
    function claimAllocation(uint256[] calldata ids_, address receiver_)
        external
        returns (uint256 totalAssetAllocation);

    /**
     * @notice Enqueues redemption of strategy allocation (shares) into stake currency
     * @dev If `readyAt` is 0, the request can be claimed immediately (sync redemption)
     * @param requestId_ Unique request ID generated outside the strategy
     * @param assetAllocation_ Amount of strategy-specific asset (shares) to redeem
     * @param user_ The address of the user requesting the exit
     * @return readyAt Earliest timestamp when the request can be claimed (0 = now)
     */
    function requestExit(uint256 requestId_, uint256 assetAllocation_, address user_)
        external
        returns (uint64 readyAt);

    /**
     * @notice Claims one or more exit requests after they become claimable
     * @param ids_ Array of request IDs to claim
     * @param receiver_ The address that will receive stake back
     * @return totalExitStakeAmount Total stake currency redeemed across all claimed requests
     */
    function claimExit(uint256[] calldata ids_, address receiver_)
        external
        returns (uint256 totalExitStakeAmount);

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    /**
     * @notice Returns true if this stake strategy is an integrated strategy
     * @dev An integrated strategy delegates all asset movements (ERC-20 tokens or native currency)
     *      to the IntegrationFacet within the same diamond. As a result:
     *        - The strategy never calls `transferFrom` or any pull for ERC20 tokens
     *        - It never needs to handle native currency transfers itself
     *        - It does not manage any ERC20 approvals itself
     *        - Both `allocate(...)` and `exit(...)` invoke the IntegrationFacet
     *          directly to move tokens internally within the diamond
     */
    function isIntegratedStakeStrategy() external view returns (bool);

    /// @return Currency used for allocation into strategy (stake)
    function stakeCurrency() external view returns (Currency calldata);

    /// @return The address of the revenue-accumulating asset (allocation asset)
    function revenueAsset() external view returns (address);

    /// @notice Preview when a new allocation would become claimable
    /// @dev Returns a timestamp (seconds). Returns 0 for synchronous deposit strategies.
    function previewAllocationReadyAt(uint256 stakeAmount_) external view returns (uint64 readyAt);

    /// @notice Preview when a new exit would become claimable
    /// @dev Returns a timestamp (seconds). Returns 0 for synchronous redeem strategies.
    function previewExitReadyAt(uint256 shares_) external view returns (uint64 readyAt);

    /// @dev Preview the asset allocation for a given stake amount
    function previewAllocation(uint256 stakeAmount_) external view returns (uint256 allocation);

    /// @dev Preview the stake amount that would be received in exchange for a given allocation
    function previewExit(uint256 assetAllocation_) external view returns (uint256 stakeAmount);

    /// @dev Request info; claimable==true if now>=readyAt and not claimed
    function requestInfo(uint256 id)
        external
        view
        returns (
            address user,
            bool isExit,            // false = allocation, true = exit
            uint256 amount,         // stake for allocation, shares for exit
            uint64 readyAt,         // 0 => claimable immediately
            bool claimed,
            bool claimable
        );

    /// @dev Batched requestInfo for multiple ids; arrays match ids_.length
    function requestInfoBatch(uint256[] calldata ids_)
        external
        view
        returns (
            address[] memory users,
            bool[] memory isExits,
            uint256[] memory amounts,
            uint64[] memory readyAts,
            bool[] memory claimedArr,
            bool[] memory claimables
        );
}
