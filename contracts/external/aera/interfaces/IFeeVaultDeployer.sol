// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.27;

import { FeeVaultParameters } from "../Types.sol";
import { IBaseVaultDeployer } from "./IBaseVaultDeployer.sol";

/// @title IFeeVaultDeployer
/// @notice Interface for the fee vault deployer
interface IFeeVaultDeployer is IBaseVaultDeployer {
    ////////////////////////////////////////////////////////////
    //                       Functions                        //
    ////////////////////////////////////////////////////////////

    /// @notice Get the deployment parameters for the fee vault
    /// @return params Deployment parameters for the fee vault
    function feeVaultParameters() external view returns (FeeVaultParameters memory params);
}
