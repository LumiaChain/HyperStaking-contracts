// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

// solhint-disable no-unused-import

// This file exists to force Hardhat to compile external contracts
// so ABIs are available for tests, scripts, and ignition

// solmate
import {RolesAuthority} from "solmate/auth/authorities/RolesAuthority.sol";

// openzeppelin
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
