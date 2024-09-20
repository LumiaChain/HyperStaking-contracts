// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.27;

// solhint-disable

import {IDepositContract} from "../interfaces/IDepositContract.sol";

// Mock contract
contract BeaconChainDepositMock is IDepositContract {
    /// @inheritdoc IDepositContract
    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) external payable {}

    /// @inheritdoc IDepositContract
    function get_deposit_count() external pure returns (bytes memory) {
        return "0x0";
    }
}
