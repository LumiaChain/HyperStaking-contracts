// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

// solhint-disable func-name-mixedcase

/**
 * @title IHyperStakingRoles
 */
interface IHyperStakingRoles {
    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error OnlyDiamondInternal();
    error OnlyStakingManager();
    error OnlyStrategyVaultManager();

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    function STAKING_MANAGER_ROLE() external view returns (bytes32);
    function STRATEGY_VAULT_MANAGER_ROLE() external view returns (bytes32);
}
