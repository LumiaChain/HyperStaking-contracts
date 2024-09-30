import { ethers } from "hardhat";
import { parseEther } from "ethers";

const DIAMOND_ADDRESS = "0xfE72b15d3Cb70224E91aBdCa5531966F48180876";
const POOL_ID = "0x5909197e2a2837216e8440fcb020f8c5959b43e88180524e1b26697ddd72b67e";
const STRATEGY_ADDRESS = "0xFeA618E29263A0501533fd438FD33618139F6E7b";

const stakeAmount = parseEther("0.3");

async function main() {
  const acc1 = (await ethers.getSigners())[0];

  const stakingFacet = await ethers.getContractAt("IStaking", DIAMOND_ADDRESS);

  const tx = await stakingFacet.stakeDeposit(POOL_ID, STRATEGY_ADDRESS, stakeAmount, acc1, { value: stakeAmount });
  console.log("TX:", tx);

  const receipt = await tx.wait();
  console.log("Receipt:", receipt);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
