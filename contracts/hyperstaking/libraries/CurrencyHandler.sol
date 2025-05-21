// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * The Currency struct represents a token
 * If `token` is address(0), it represents native coins (e.g. ETH)
 * @param token Address of the token, address(0) means native chain coin (e.g. ETH)
 */
struct Currency {
    address token;
}

/**
 * @title CurrencyHandler Library
 * @dev This library provides a unified way to handle ERC20 tokens and native coins (e.g., ETH)
 * It simplifies transferring and approving tokens/coins by using a common structure for tokens
 * and allowing safe transfers via OpenZeppelin's SafeERC20 library
 *
 * Usage: The library handles ERC20 transfers and approvals as well as native chain currency
 * depending on the token address input (use address(0) for native coin)
 */

library CurrencyHandler {
    using SafeERC20 for IERC20;

    /**
     * @notice Simple check, if the given currency is a native coin
     * @param currency The Currency struct (token address or native coin)
     */
    function isNativeCoin(Currency memory currency) internal pure returns (bool) {
        return currency.token == address(0);
    }

    /**
     * @notice Returns the balance of a given account for the specified currency
     * @dev If the currency is a native coin, it returns the native balance of the account
     *      Otherwise, it retrieves the balance from the ERC-20 contract
     * @param currency The Currency struct (token address or native coin)
     * @param account The address of the account to query the balance for
     * @return The balance of the specified account in the given currency
     */
    function balanceOf(
        Currency memory currency,
        address account
    ) internal view returns (uint256) {
        if (isNativeCoin(currency)) {
            return account.balance;
        } else {
            return IERC20(currency.token).balanceOf(account);
        }
    }

    /**
     * @dev Transfers tokens or native coins to a recipient
     * @param currency The Currency struct (token address or native coin)
     * @param recipient The address of the recipient to receive the funds
     * @param amount The amount of the token/native coin to transfer
     */
    function transfer(
        Currency memory currency,
        address recipient,
        uint256 amount
    ) internal {
        if (isNativeCoin(currency)) {
            require(address(this).balance >= amount, "Transfer insufficient balance");

            // Transfer native coin (ETH) to recipient
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "Transfer call failed");
        } else {
            IERC20(currency.token).safeTransfer(recipient, amount);
        }
    }

    /**
     * @dev Transfers tokens or native coins from one address to another
     * For ERC20 tokens, it uses `transferFrom`
     * For native chain coins, it checks if `msg.value` is sufficient
     * @param currency The Currency struct (token address or native coin)
     * @param from The address from which the tokens/coins will be transferred
     * @param to The recipient address
     * @param amount The amount of tokens/native coin to transfer
     */
    function transferFrom(
        Currency memory currency,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (isNativeCoin(currency)) {
            // native coin transfer: only check
            require(msg.value >= amount, "Insufficient native value");

        } else {
            IERC20(currency.token).safeTransferFrom(from, to, amount);
        }
    }

    /**
     * @dev Approves tokens to be spent by a spender. This applies only to ERC20 tokens
     * No approval is needed for native coins
     *
     * WARNING: Calling ERC20.approve directly can be unsafe when changing an existing
     * non-zero allowance, since a front-running spender could use both the old and new
     * allowance. Consider using increaseAllowance/decreaseAllowance or SafeERC20 helpers
     *
     * @param currency The Currency struct (token address)
     * @param spender The address of the spender allowed to spend the tokens
     * @param amount The amount of tokens to approve for spending
     */
    function approve(
        Currency memory currency,
        address spender,
        uint256 amount
    ) internal {
        // Revert if the currency is a native coin, as native coins don't use pull pattern
        // Make sure to check that the currency is an ERC20 token before calling approve
        if (isNativeCoin(currency)) {
            revert("Approve not allowed for native coins");
        }

        IERC20(currency.token).approve(spender, amount);
    }

    /**
     * @dev Safely increases the ERC20 allowance granted to `spender` by the caller
     * Reverts if `currency` is native (no approval mechanism)
     * @param currency The Currency struct (token address)
     * @param spender The address allowed to spend the tokens
     * @param addedValue The amount by which to increase the allowance
     */
    function increaseAllowance(
        Currency memory currency,
        address spender,
        uint256 addedValue
    ) internal {
        if (isNativeCoin(currency)) {
            revert("Increase not allowed for native coins");
        }
        IERC20(currency.token).safeIncreaseAllowance(spender, addedValue);
    }

    /**
     * @dev Safely decreases the ERC20 allowance granted to `spender` by the caller
     * Reverts if `currency` is native (no approval mechanism) or if
     * the current allowance is less than `subtractedValue`
     * @param currency The Currency struct (token address)
     * @param spender The address whose allowance is to be decreased
     * @param subtractedValue The amount by which to decrease the allowance
     */
    function decreaseAllowance(
        Currency memory currency,
        address spender,
        uint256 subtractedValue
    ) internal {
        if (isNativeCoin(currency)) {
            revert("Decrease not allowed for native coins");
        }
        IERC20(currency.token).safeDecreaseAllowance(spender, subtractedValue);
    }

    /**
     * @notice Gets the decimals for a given currency
     * @param currency The Currency struct, containing the token address
     * @return The number of decimals used by the currency. Returns 18 for native coin
     */
    function decimals(Currency memory currency) internal view returns (uint8) {
        if (currency.token == address(0)) {
            return 18; // Assume native tokens have 18 decimals
        }
        return IERC20Metadata(currency.token).decimals();
    }
}
