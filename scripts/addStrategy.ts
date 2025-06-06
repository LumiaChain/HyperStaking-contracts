import { ethers } from "hardhat";
import { parseEther } from "ethers";

import * as holeskyAddresses from "../ignition/parameters.holesky.json";

const FEE_RATE = parseEther("0.02"); // 2% fee

async function main() {
  const vaultManager = (await ethers.getSigners())[2];
  console.log("vault manager:", vaultManager.address);

  const network = await ethers.provider.getNetwork();
  console.log("network:", network.name, ", chainId:", network.chainId);

  const diamond = holeskyAddresses.General.diamond;
  const strategy = holeskyAddresses.General.dineroStrategy;
  const vaultAsset = holeskyAddresses.DineroStrategyModule.autoPxEth;

  console.log("diamond address:", diamond);
  console.log("strategy address:", strategy);
  console.log("vault asset:", vaultAsset);
  console.log("report fee:", FEE_RATE.toString());

  const factoryFacet = await ethers.getContractAt("IHyperFactory", diamond);

  const vaultTokenName = "eth vault";
  const vaultTokenSymbol = "vETH";

  let tx = await factoryFacet.connect(vaultManager).addStrategy(
    strategy,
    vaultTokenName,
    vaultTokenSymbol,
  );

  console.log("[addStrategy] TX:", tx.hash);
  const receipt = await tx.wait();

  console.log("Receipt:", receipt);

  // Configuration

  const allocationFacet = await ethers.getContractAt("IAllocation", diamond);
  tx = await allocationFacet.connect(vaultManager).setFeeRecipient(
    strategy,
    vaultManager,
  );

  console.log("[setFeeRecipient] TX:", tx.hash);
  await tx.wait();
  console.log("Fee recipient set to:", vaultManager.address);

  tx = await allocationFacet.connect(vaultManager).setFeeRate(
    strategy,
    FEE_RATE,
  );

  console.log("[setFeeRate] TX:", tx.hash);
  await tx.wait();
  console.log("Fee rate set to:", FEE_RATE.toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
