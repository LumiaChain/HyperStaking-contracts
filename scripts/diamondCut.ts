import { ethers } from "hardhat";
import { FacetCutAction, printSelector, getSelectors } from "./libraries/diamond";
import { diffFacetSelectors } from "./libraries/diamondLoupe";
import { getContractInterface } from "./libraries/hardhat";
import promptSync from "prompt-sync";

import { ZeroAddress } from "ethers";

import * as addresses from "../ignition/parameters.sepolia.json";
import { processTx } from "./libraries/utils";

// This script upgrades a facet in a Diamond by deploying a new facet contract
// replacing the old one. It compares the function selectors of the old and new facet
// to determine which selectors need to be added, replaced, or removed

// Instructions:
// 1. Set the OLD_FACET_ADDRESS to the address of the facet you want to replace.
// 2. Set the FACET_CONTRACT_NAME to the name of the new facet contract.
// 3. Set the FACET_CONTRACT_INTERFACE to the interface name of the new facet contract.
// 4. Run the script using `npx hardhat run --network <network> scripts/diamondCut.ts`

const OLD_FACET_ADDRESS = "";

const FACET_CONTRACT_NAME = "";
const FACET_CONTRACT_INTERFACE = "";

async function main() {
  const diamond = addresses.General.diamond;

  console.log(
    `Upgrading facet ${FACET_CONTRACT_NAME} at address: ${OLD_FACET_ADDRESS} in diamond: ${diamond}`,
  );
  console.log("\n");

  // -- Diff facet selectors

  const facetInterface = getContractInterface(FACET_CONTRACT_INTERFACE);

  const { addSelectors, replaceSelectors, removeSelectors } =
    await diffFacetSelectors(
      diamond,
      OLD_FACET_ADDRESS,
      facetInterface,
    );

  // ACL selectors are added to DepositFacet, so we should not remove them
  if (FACET_CONTRACT_NAME === "DepositFacet") {
    const aclInterface = getContractInterface("HyperStakingAcl");
    const aclInterfaceSelectors = getSelectors(aclInterface).remove(["supportsInterface(bytes4)"]);

    for (const selector of aclInterfaceSelectors) {
      const index = removeSelectors.indexOf(selector);
      if (index !== -1) {
        removeSelectors.splice(index, 1);
      }
    }
  }

  console.log("Selectors to add:", addSelectors.map((s) => printSelector(facetInterface, s)));
  console.log("Selectors to replace:", replaceSelectors.map((s) => printSelector(facetInterface, s)));
  console.log("Selectors to remove:", removeSelectors.map((s) => printSelector(facetInterface, s)));
  console.log("\n");

  // are you sure to continue?
  const prompt = promptSync({ sigint: true });
  const answer = prompt("Do you want to continue? (yes/no): ")?.trim().toLowerCase();
  if (answer !== "yes") {
    console.log("Exiting");
    return;
  }

  // -- Deploy new facet

  const newFacet = await ethers.deployContract(FACET_CONTRACT_NAME);
  await newFacet.waitForDeployment();
  console.log(`Deployed new facet ${FACET_CONTRACT_NAME} at address:`, newFacet.target);

  // -- Prepare diamond cut

  const cut = [];

  if (addSelectors.length > 0) {
    cut.push({
      facetAddress: newFacet.target,
      action: FacetCutAction.Add,
      functionSelectors: addSelectors,
    });
  }

  if (replaceSelectors.length > 0) {
    cut.push({
      facetAddress: newFacet.target,
      action: FacetCutAction.Replace,
      functionSelectors: replaceSelectors,
    });
  }

  if (removeSelectors.length > 0) {
    cut.push({
      facetAddress: OLD_FACET_ADDRESS,
      action: FacetCutAction.Remove,
      functionSelectors: removeSelectors,
    });
  }

  if (cut.length === 0) {
    console.log("No changes in facet selectors. Exiting.");
    return;
  }

  // -- Execute diamond cut

  const diamondCut = await ethers.getContractAt(
    "IDiamondCut",
    diamond,
  );

  const tx = await diamondCut.diamondCut(cut, ZeroAddress, "0x");
  await processTx(tx, "Diamond cut");

  console.log("Finished");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
