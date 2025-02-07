import { ethers } from "hardhat";
import { getSelectors, FacetCutAction } from "./libraries/diamond";
import { getContractInterface } from "./libraries/hardhat";

import { ZeroAddress } from "ethers";

import * as holeskyAddresses from "../ignition/parameters.holesky.json";

async function main() {
  const diamond = holeskyAddresses.General.diamond;

  const newHyperFactoryFacet = await ethers.deployContract("HyperFactoryFacet");
  await newHyperFactoryFacet.waitForDeployment();

  // const newHyperFactoryFacet = await ethers.getContractAt("IHyperFactory", FACET_ADDRESS);

  console.log("new HyperFactoryFacet address:", newHyperFactoryFacet.target);

  const facetInterface = getContractInterface("IHyperFactory");
  const selectors = getSelectors(facetInterface);
  // const selectors = getSelectors(facetInterface).getByNames(["deposit"]);
  console.log("Selectors:", selectors);

  const cut = [
    {
      facetAddress: newHyperFactoryFacet.target,
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
