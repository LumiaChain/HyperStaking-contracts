// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title ILumiaVaultShares
 * @dev Extends the standard IERC4626 with spendAllowance functionality
 */
interface ILumiaVaultShares is IERC4626 {
    /**
     * @notice Allows the owner of the vault to spend allowance on behalf of a user
     *         Useful for enabling external contracts (e.g., management contracts)
     *         to redeem shares on behalf of users
     * @dev Reverts if the allowance is insufficient
     * @param owner The address that granted the allowance
     * @param caller The address attempting to spend the allowance
     * @param shares The number of shares to spend
     */
    function spendAllowance(
        address owner,
        address caller,
        uint256 shares
    ) external;
}
