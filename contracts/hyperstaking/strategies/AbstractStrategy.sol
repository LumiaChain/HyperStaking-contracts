// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {StrategyKind, StrategyRequest, IStrategy} from "../interfaces/IStrategy.sol";
import {Currency, CurrencyHandler} from "../libraries/CurrencyHandler.sol";
import {IHyperStakingRoles} from "../interfaces/IHyperStakingRoles.sol";

/**
 * @title AbstractStrategy
 */
abstract contract AbstractStrategy is IStrategy {
    using CurrencyHandler for Currency;

    /// Diamond deployment address
    address public immutable DIAMOND;

    /// Stores all requests both allocations and exits
    mapping(uint256 id => StrategyRequest) internal _req;

    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event EmergencyWithdraw(
        address indexed sender,
        address indexed currencyToken,
        uint256 amount,
        address indexed to
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error ZeroAddress();
    error ZeroAmount();

    error ZeroUser();
    error RequestIdExists(uint256 id);

    error NotLumiaDiamond();
    error NotStrategyManager();
    error DontSupportArrays();

    error AlreadyClaimed();
    error NotReady();
    error WrongKind();

    //============================================================================================//
    //                                         Modifiers                                          //
    //============================================================================================//

    modifier onlyLumiaDiamond() {
        require(msg.sender == DIAMOND, NotLumiaDiamond());
        _;
    }

    modifier onlyStrategyManager() {
        require(
            IHyperStakingRoles(DIAMOND).hasStrategyManagerRole(msg.sender),
            NotStrategyManager()
        );
        _;
    }

    //============================================================================================//
    //                                        Constructor                                         //
    //============================================================================================//

    constructor(
        address diamond_
    ) {
        require(diamond_ != address(0), ZeroAddress());

        DIAMOND = diamond_;
    }

    //============================================================================================//
    //                                      Public Functions                                      //
    //============================================================================================//

    // ========= Previews ========= //

    /// @dev Raw conversion without invariants (strategy-specific)
    function _previewAllocationRaw(uint256 stake_) internal view virtual returns (uint256);

    /// @dev Raw reverse conversion without invariants (strategy-specific)
    function _previewExitRaw(uint256 allocation_) internal view virtual returns (uint256);

    /// @inheritdoc IStrategy
    function previewAllocation(
        uint256 stake_
    ) public view virtual override returns (uint256 allocation) {
        allocation = _previewAllocationRaw(stake_);

        // round up by 1 wei if needed to avoid loss on conversion (ceil adjustment)
        if (_previewExitRaw(allocation) < stake_) {
            unchecked { ++allocation; }
        }
    }

    /// @inheritdoc IStrategy
    function previewExit(
        uint256 allocation_
    ) public view virtual override returns (uint256 stake) {
        stake = _previewExitRaw(allocation_);
    }

    // ========= Flags ========= //

    /// @inheritdoc IStrategy
    function isDirectStakeStrategy() external pure virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IStrategy
    function isIntegratedStakeStrategy() external pure virtual returns (bool) {
        return false;
    }

    // ========= Requests ========= //

    /// @dev Returns requestInfo for a given id
    function requestInfo(uint256 id_)
        external
        view
        returns (
            address user,
            bool isExit,
            uint256 amount,
            uint64 readyAt,
            bool claimable,
            bool claimed
        )
    {
        StrategyRequest memory r = _req[id_];
        user = r.user;
        isExit = (r.kind == StrategyKind.Exit);
        amount = r.amount;
        readyAt = r.readyAt;
        claimed = r.claimed;
        claimable = (!claimed && block.timestamp >= readyAt);
    }

    /// @dev Batched requestInfo for multiple ids; arrays match ids_.length
    function requestInfoBatch(uint256[] calldata ids_)
        external
        view
        returns (
            address[] memory users,
            bool[] memory isExits,
            uint256[] memory amounts,
            uint64[] memory readyAts,
            bool[] memory claimables,
            bool[] memory claimedArr
        )
    {
        uint256 n = ids_.length;
        users = new address[](n);
        isExits = new bool[](n);
        amounts = new uint256[](n);
        readyAts = new uint64[](n);
        claimables = new bool[](n);
        claimedArr = new bool[](n);

        for (uint256 i; i < n; ++i) {
            StrategyRequest memory r = _req[ids_[i]];
            users[i] = r.user;
            isExits[i] = (r.kind == StrategyKind.Exit);
            amounts[i] = r.amount;
            readyAts[i] = r.readyAt;
            claimedArr[i] = r.claimed;
            claimables[i] = (!r.claimed && block.timestamp >= r.readyAt);
        }
    }

    // ========= StrategyManager ========= //

    /**
     * @notice Emergency withdrawal function for StrategyManagers
     * @dev This should only be used in exceptional cases where tokens are stuck
     *      Strategies should be implemented to ensure funds do not become stranded
     * @param currency_ The currency to withdraw (native or erc20)
     * @param amount_ The amount to withdraw
     * @param to_ The recipient address
     */
    function emergencyWithdrawal(
        Currency memory currency_,
        uint256 amount_,
        address to_
    ) external onlyStrategyManager {
        currency_.transfer(to_, amount_);
        emit EmergencyWithdraw(msg.sender, currency_.token, amount_, to_);
    }

    //============================================================================================//
    //                                     Internal Functions                                     //
    //============================================================================================//

    // ========= Request Helpers ========= //

    /// @dev Stores a new allocation request in _req mapping
    function _storeAllocationRequest(
        uint256 id_,
        address user_,
        uint256 amount_,
        uint64 readyAt_
    ) internal {
        require(user_ != address(0), ZeroUser());
        require(_req[id_].user == address(0), RequestIdExists(id_));

        _req[id_] = StrategyRequest({
            user: user_,
            kind: StrategyKind.Allocation,
            claimed: false,
            amount: amount_,
            readyAt: readyAt_
        });
    }

    /// @dev Stores a new exit request in _req mapping
    function _storeExitRequest(
        uint256 id_,
        address user_,
        uint256 shares_,
        uint64 readyAt_
    ) internal {
        require(user_ != address(0), ZeroUser());
        require(_req[id_].user == address(0), RequestIdExists(id_));

        _req[id_] = StrategyRequest({
            user: user_,
            kind: StrategyKind.Exit,
            claimed: false,
            amount: shares_,
            readyAt: readyAt_
        });
    }

    /// @dev Loads a request and pre-validates it
    function _loadClaimable(
        uint256 id_,
        StrategyKind expected_
    ) internal view returns (StrategyRequest memory r) {
        r = _req[id_];
        require(!r.claimed, AlreadyClaimed());
        require(r.kind == expected_, WrongKind());
        require(block.timestamp >= r.readyAt, NotReady());
    }

    /// @dev Marks a request as claimed
    function _markClaimed(uint256 id_) internal {
        _req[id_].claimed = true;
    }
}
