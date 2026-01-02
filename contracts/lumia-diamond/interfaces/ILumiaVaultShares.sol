// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title ILumiaVaultShares
 * @dev Extends the standard IERC4626 with diamondRedeem functionality
 */
interface ILumiaVaultShares is IERC4626 {
    /**
     * @notice Redeems shares using the diamond as the owner
     * @dev Mirrors the standard ERC4626 redeem flow but takes `caller` explicitly
     *      `caller` must be the original msg.sender from the diamond facet
     *      Allowance is checked in _withdraw against `caller` when `caller != owner`
     *
     *      Function owned by a diamond facet that is a trusted component, must correctly pass
     *      the original transaction initiator as the caller parameter
     */
    function diamondRedeem(
        uint256 shares,
        address caller,
        address receiver,
        address owner
    ) external returns (uint256);
}
