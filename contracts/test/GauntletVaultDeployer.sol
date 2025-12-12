// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {MultiDepositorVault} from "../external/aera/MultiDepositorVault.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {Authority} from "solmate/auth/Auth.sol";
import {Auth2Step} from "../external/aera/Auth2Step.sol";

import {IBeforeTransferHook} from "../external/aera/interfaces/IBeforeTransferHook.sol";
import {IFeeCalculator} from "../external/aera/interfaces/IFeeCalculator.sol";
import {ISubmitHooks} from "../external/aera/interfaces/ISubmitHooks.sol";
import {IWhitelist} from "../external/aera/interfaces/IWhitelist.sol";

import {
    IMultiDepositorVaultFactory,
    BaseVaultParameters,
    ERC20Parameters,
    FeeVaultParameters
} from "../external/aera/interfaces/IMultiDepositorVaultFactory.sol";

/**
 * @notice Small mock factory used only to deploy a vault and provide constructor params
 *         The vault pulls name, symbol and hook from this contract via msg.sender
 */
contract GauntletVaultDeployer is IMultiDepositorVaultFactory {
    /// @notice ERC20 name returned to the vault during construction
    string private _name;

    /// @notice ERC20 symbol returned to the vault during construction
    string private _symbol;

    /// @notice Owner set during construction
    address private _owner;

    /// @notice Authority set during construction
    Authority private _authority;

    /// @notice Hook instance returned to the vault during construction
    IBeforeTransferHook private _hook;

    /// @notice Fee parameters set during construction
    FeeVaultParameters private _feeVaultParameters;

    /// @notice Emitted after a new vault is deployed
    event VaultDeployed(address vault);

    /// @notice Set fixed parameters that the vault will read from this factory
    /// @dev Use address(0) for hook_ to disable the transfer hook in the vault
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        address authority_,
        address hook_,
        address feeCalculator_,
        address feeToken_,
        address feeReceiver_
    ) {
        _name = name_;
        _symbol = symbol_;

        _owner = owner_;
        _authority = Authority(authority_);
        _hook = IBeforeTransferHook(hook_);

        _feeVaultParameters.feeCalculator = IFeeCalculator(feeCalculator_);
        _feeVaultParameters.feeToken = IERC20(feeToken_);
        _feeVaultParameters.feeRecipient = feeReceiver_;
    }

    /// @notice Deploy a new MultiDepositorVault so that msg.sender equals this factory
    function deploy() public returns (address vault) {
        vault = address(new MultiDepositorVault());
        Auth2Step(vault).transferOwnership(msg.sender);
        emit VaultDeployed(vault);
    }

    function getERC20Name() external view returns (string memory) {
        return _name;
    }

    function getERC20Symbol() external view returns (string memory) {
        return _symbol;
    }

    /// @notice Parameters read by the vault to set its before transfer hook
    function multiDepositorVaultParameters()
        external
        view
        returns (IBeforeTransferHook)
    {
        return _hook;
    }

    /// @dev Dummy implementation to satisfy IMultiDepositorVaultFactory
    function create(
        bytes32,
        string calldata,
        ERC20Parameters calldata,
        BaseVaultParameters calldata,
        FeeVaultParameters calldata,
        IBeforeTransferHook,
        address
    ) external returns (address deployedVault) {
        deployedVault = deploy();
    }

    /// @dev Satisfy IFeeVaultDeployer
    function feeVaultParameters() external view returns (FeeVaultParameters memory) {
        return _feeVaultParameters;
    }

    /// @dev Satisfy IBaseVaultDeployer
    function baseVaultParameters() external view returns (BaseVaultParameters memory params) {
        params.owner = _owner;
        params.authority = Authority(_authority);
        params.submitHooks = ISubmitHooks(address(0));
        params.whitelist = IWhitelist(address(0));
    }
}
