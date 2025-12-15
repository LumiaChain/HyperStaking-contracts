// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

//============================================================================================//
//                                    Shared Errors                                           //
//============================================================================================//

error NotAuthorized(address);

error ZeroAddress();
error ZeroAmount();

error ZeroStakeExit();
error ZeroAllocationExit();

error UpdateFailed();

// cross-chain error
error BadOriginDestination(uint32 originDestination);
