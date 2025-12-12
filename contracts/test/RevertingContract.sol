// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;


contract RevertingContract {
    receive() external payable {
        revert("Force call failure");
    }
}
