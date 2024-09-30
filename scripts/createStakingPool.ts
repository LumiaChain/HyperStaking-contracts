import { ethers } from "hardhat";

const DIAMOND_ADDRESS = "0xfE72b15d3Cb70224E91aBdCa5531966F48180876";
// const TOKEN_ADDRESS = "0x";

async function main() {
  const stakingFacet = await ethers.getContractAt("IStaking", DIAMOND_ADDRESS);

  const nativeTokenAddress = await stakingFacet.nativeTokenAddress();
  console.log("Native token address:", nativeTokenAddress);

  const TOKEN_ADDRESS = nativeTokenAddress;

  console.log("Creating staking pool...");
  const tx = await stakingFacet.createStakingPool(TOKEN_ADDRESS);
  console.log("TX:", tx);
  await tx.wait();

  const idx = await stakingFacet.stakeTokenPoolCount(TOKEN_ADDRESS);
  console.log("Pool idx:", idx);
  const poolId = await stakingFacet.generatePoolId(TOKEN_ADDRESS, idx - 1n);

  if (TOKEN_ADDRESS === nativeTokenAddress) {
    console.log(`Staking pool for native token created, id: 0x${poolId.toString(16)}`);
  } else {
    console.log(`Staking pool for token ${TOKEN_ADDRESS} created, id: 0x${poolId.toString(16)}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
