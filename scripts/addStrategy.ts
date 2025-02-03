import { ethers } from "hardhat";
import { parseEther } from "ethers";

import * as holeskyAddresses from "../ignition/parameters.holesky.json";

const REVENUE_FEE = parseEther("0.02"); // 2% fee

async function main() {
  const strategyVaultManager = (await ethers.getSigners())[2];
  console.log("strategy manager:", strategyVaultManager.address);

  const network = await ethers.provider.getNetwork();
  console.log("network:", network.name, ", chainId:", network.chainId);

  const diamond = holeskyAddresses.General.diamond;
  const strategy = holeskyAddresses.General.dineroStrategy;
  const vaultAsset = holeskyAddresses.DineroStrategyModule.autoPxEth;
  const poolId = holeskyAddresses.General.defaultNativePool;

  console.log("diamond address:", diamond);
  console.log("strategy address:", strategy);
  console.log("vault asset:", vaultAsset);
  console.log("pool id:", poolId);
  console.log("revenue fee:", REVENUE_FEE.toString());

  const factoryFacet = await ethers.getContractAt("IVaultFactory", diamond);

  const vaultTokenName = "eth vault";
  const vaultTokenSymbol = "vETH";

  const tx = await factoryFacet.connect(strategyVaultManager).addStrategy(
    poolId,
    strategy,
    vaultTokenName,
    vaultTokenSymbol,
    REVENUE_FEE,
  );

  console.log("TX:", tx);
  const receipt = await tx.wait();

  console.log("Receipt:", receipt);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
