import { ethers } from "hardhat";

const DIAMOND_ADDRESS = "0xfE72b15d3Cb70224E91aBdCa5531966F48180876";
const POOL_ID = "0x5909197e2a2837216e8440fcb020f8c5959b43e88180524e1b26697ddd72b67e";
const STRATEGY_ADDRESS = "0xFeA618E29263A0501533fd438FD33618139F6E7b";
const VAULT_TOKEN = "0x0e4bf0D7e9198756B821446C6Fb7A17Dfbfca198"; // apxETH, testnet (holesky)

async function main() {
  const vaultFacet = await ethers.getContractAt("IStrategyVault", DIAMOND_ADDRESS);

  const tx = await vaultFacet.addStrategy(POOL_ID, STRATEGY_ADDRESS, VAULT_TOKEN);
  console.log("TX:", tx);
  const receipt = await tx.wait();

  console.log("Receipt:", receipt);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
