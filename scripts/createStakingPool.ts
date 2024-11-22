import { ethers } from "hardhat";
import { ZeroAddress } from "ethers";
import { CurrencyStruct } from "../typechain-types/contracts/hyperstaking/facets/StakingFacet";

import * as holeskyDeployment from "../ignition/deployments/holesky/deployed_addresses.json";

async function main() {
  const stakingManager = (await ethers.getSigners())[1];

  const network = await ethers.provider.getNetwork();
  console.log("network:", network.name, ", chainId:", network.chainId);

  const diamondAddress = holeskyDeployment["DiamondModule#Diamond"];
  console.log("diamond address:", diamondAddress);

  const stakingFacet = await ethers.getContractAt("IStaking", diamondAddress);

  // the pool is created for the native coin
  const nativeTokenAddress = ZeroAddress;
  const currency = { token: nativeTokenAddress } as CurrencyStruct;

  console.log("Creating staking pool...");
  const tx = await stakingFacet.connect(stakingManager).createStakingPool(currency);
  console.log("TX:", tx);
  await tx.wait();

  const poolCount = await stakingFacet.stakeTokenPoolCount(currency);
  const poolIdx = poolCount - 1n;

  console.log("Pool idx:", poolIdx);
  const poolId = await stakingFacet.generatePoolId(currency, poolIdx);

  if (currency.token === ZeroAddress) {
    console.log(`Staking pool for native token created, id: 0x${poolId.toString(16)}`);
  } else {
    console.log(`Staking pool for token ${currency.token} created, id: 0x${poolId.toString(16)}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
