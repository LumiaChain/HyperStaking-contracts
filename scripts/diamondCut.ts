import { ethers } from "hardhat";
import { getSelectors, FacetCutAction } from "./libraries/diamond";
import { getContractInterface } from "./libraries/hardhat";

import { ZeroAddress } from "ethers";

import * as holeskyAddresses from "../ignition/parameters.holesky.json";

async function main() {
  const diamond = holeskyAddresses.General.diamond;

  const newVaultFactoryFacet = await ethers.deployContract("VaultFactoryFacet");
  await newVaultFactoryFacet.waitForDeployment();

  // const newVaultFactoryFacet = await ethers.getContractAt("IVaultFactory", FACET_ADDRESS);

  console.log("new VaultFactoryFacet address:", newVaultFactoryFacet.target);

  const facetInterface = getContractInterface("IVaultFactory");
  const selectors = getSelectors(facetInterface);
  // const selectors = getSelectors(facetInterface).getByNames(["deposit"]);
  console.log("Selectors:", selectors);

  const cut = [
    {
      facetAddress: newVaultFactoryFacet.target,
      action: FacetCutAction.Replace,
      functionSelectors: selectors,
    },
  ];

  const diamondCut = await ethers.getContractAt(
    "IDiamondCut",
    diamond,
  );

  console.log(cut);

  const tx = await diamondCut.diamondCut(cut, ZeroAddress, "0x");
  console.log("Tx:", tx);

  const receipt = await tx.wait();
  console.log("Receipt:", receipt);

  console.log("Finished");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
