// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IBaseRouterImplementation} from "../../external/superform/core/interfaces/IBaseRouterImplementation.sol";
import {ISuperformFactory} from "../../external/superform/core/interfaces/ISuperformFactory.sol";
import {ISuperPositions} from "../../external/superform/core/interfaces/ISuperPositions.sol";

/**
 * @title ISuperformIntegration
 * @dev Interface for SuperformIntegrationFacet
 */
interface ISuperformIntegration {
    //============================================================================================//
    //                                          Events                                            //
    //============================================================================================//

    event MaxSlippageUpdated(uint256 oldMaxSlippage, uint256 newMaxSlippage);
    event SuperformFactoryUpdated(address oldFactory, address newFactory);
    event SuperformRouterUpdated(address oldRouter, address newRouter);
    event SuperPositionsUpdated(address oldSuperPositions, address newSuperPositions);

    event SuperformStrategyUpdated(address strategy, bool status);

    event SuperformSingleVaultDeposit(
        uint256 indexed superformId,
        uint256 assetAmount,
        address indexed receiver,
        address indexed receiverSP,
        uint256 superPositionsReceived
    );

    event SuperformSingleVaultWithdraw(
        uint256 indexed superformId,
        uint256 superPositionAmount,
        address indexed receiver,
        address indexed receiverSP,
        uint256 assetReceived
    );

    //============================================================================================//
    //                                          Errors                                            //
    //============================================================================================//

    error InvalidSuperformId(uint256 superformId);
    error ZeroAmount();
    error ZeroAddress();
    error NotFromStrategy(address);

    //============================================================================================//
    //                                          Mutable                                           //
    //============================================================================================//

    /**
     * @notice Deposits assets into a single vault
     * @return superPositionReceived Amount of Superform positions minted
     */
    function singleVaultDeposit(
        uint256 superformId_,
        uint256 assetAmount_,
        address receiver_,
        address receiverSP_
    ) external returns (uint256 superPositionReceived);

    /**
     * @notice Withdraws assets from a single vault
     * @return assetReceived Amount of assets withdrawn from the vault
     */
    function singleVaultWithdraw(
        uint256 superformId_,
        uint256 superPositionAmount_,
        address receiver_,
        address receiverSP_
    ) external returns (uint256 assetReceived);

    /**
     * @dev Updates the status of a Superform strategy
     * @param strategy The address of the strategy to update
     * @param status The new status of the strategy (true to enable, false to disable)
     */
    function updateSuperformStrategies(address strategy, bool status) external;

    /**
     * @dev Sets the maximum slippage used in superform, where 10000 = 100%
     */
    function setMaxSlippage(uint256 newMaxSlippage) external;

    //============================================================================================//
    //                                           View                                             //
    //============================================================================================//

    function superformStrategyAt(uint256 index) external view returns (address);

    function superformStrategiesLength() external view returns (uint256);

    function getMaxSlippage() external view returns (uint256);

    function superformFactory() external view returns (ISuperformFactory);

    function superformRouter() external view returns (IBaseRouterImplementation);

    function superPositions() external view returns (ISuperPositions);
}
