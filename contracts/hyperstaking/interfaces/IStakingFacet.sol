// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

// import {PoolInfo} from "../libraries/LibStaking.sol";

/**
 * @title IStakingFacet
 * @dev Interface for StakingFacet
 */
interface IStakingFacet {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event StakeDeposit(
        address indexed from,
        uint256 indexed poolId,
        uint256 amount,
        address indexed to
    );

    event StakeWithdraw(
        address indexed from,
        uint256 indexed poolId,
        uint256 amount,
        address indexed to
    );

    event StakingPoolCreate(
        address indexed from,
        address indexed stakeToken,
        uint256 idx,
        uint256 poolId
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    /// @notice Thrown when the provided eth value is incorrect
    error DepositBadValue();

    /// @dev TODO remove
    error Unsupported();

    /// @notice Thrown when failed to transfer ETH value (with call)
    error WithdrawFailedCall();

    /// @notice Thrown when attempting to access a non-existent staking pool
    error PoolDoesNotExist();

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    function init() external;

    function stakeDeposit(uint256 poolId, uint256 amount, address to) external payable;

    function stakeWithdraw(uint256 poolId, uint256 amount, address to) external;


    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    function nativeTokenAddress() external returns (address);

    function generatePoolId(address stakeToken, uint256 idx) external view returns (uint256);
}
