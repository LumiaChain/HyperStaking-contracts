import { ethers } from "hardhat";
import { getSelectors, FacetCutAction } from "./libraries/diamond";
import { getContractInterface } from "./libraries/hardhat";

import { ZeroAddress } from "ethers";

const DIAMOND_ADDRESS = "0xfE72b15d3Cb70224E91aBdCa5531966F48180876";
// const FACET_ADDRESS = "0xde53c05e25328C1Ac90d9d1dE57291171361ba76";

async function main() {
  const newVaultFacet = await ethers.deployContract("StrategyVaultFacet");
  await newVaultFacet.waitForDeployment();

  // const newVaultFacet = await ethers.getContractAt("StrategyVaultFacet", FACET_ADDRESS);
  console.log("vaultFacet address:", newVaultFacet.target);

  const facetInterface = getContractInterface("IStrategyVault");
  const selectors = getSelectors(facetInterface).getByNames(["deposit"]);
  console.log("Selectors:", selectors);

  const cut = [
    {
      facetAddress: newVaultFacet.target,
      action: FacetCutAction.Replace,
      functionSelectors: selectors,
    },
  ];

  const diamondCut = await ethers.getContractAt(
    "IDiamondCut",
    DIAMOND_ADDRESS,
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
