// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * The Currency struct represents a token.
 * If `token` is address(0), it represents native coins (e.g. ETH).
 * @param token Address of the token, address(0) means native chain coin (e.g. ETH)
 */
struct Currency {
    address token;
}

/**
 * @title CurrencyHandler Library
 * @dev This library provides a unified way to handle ERC20 tokens and native coins (e.g., ETH).
 * It simplifies transferring and approving tokens/coins by using a common structure for tokens
 * and allowing safe transfers via OpenZeppelin's SafeERC20 library.
 *
 * Usage: The library handles ERC20 transfers and approvals as well as native chain currency
 * depending on the token address input (use address(0) for native coin).
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
     * @dev Transfers tokens or native coins to a recipient.
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
     * @dev Transfers tokens or native coins from one address to another.
     * For ERC20 tokens, it uses `transferFrom`.
     * For native chain coins, it checks if `msg.value` matches the amount.
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
            // Native coin transfer: Check if the value matches the intended amount
            require(msg.value == amount, "Invalid native value sent");

        } else {
            IERC20(currency.token).safeTransferFrom(from, to, amount);
        }
    }

    /**
     * @dev Approves tokens to be spent by a spender. This applies only to ERC20 tokens.
     * No approval is needed for native coins.
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
}
