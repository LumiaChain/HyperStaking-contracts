import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { getSelectors, FacetCutAction } from "../../scripts/libraries/diamond";
import { getContractInterface } from "../../scripts/libraries/hardhat";

const DiamondModule = buildModule("DiamondModule", (m) => {
  const owner = m.getAccount(0);
  const diamondCutFacet = m.contract("DiamondCutFacet");
  const diamond = m.contract("Diamond", [owner, diamondCutFacet], {});

  const diamondInit = m.contract("DiamondInit");

  const facetNames = [
    "DiamondLoupeFacet",
    "OwnershipFacet",
  ];
  const cut = [];
  for (const facetName of facetNames) {
    const facetInterface = getContractInterface(facetName);
    const facet = m.contract(facetName);

    cut.push({
      facetAddress: facet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(facetInterface),
    });
  }

  const diamondInitInterface = getContractInterface("DiamondInit");
  const functionCall = diamondInitInterface.encodeFunctionData("init");

  const diamondCut = m.contractAt("IDiamondCut", diamond);
  m.call(diamondCut, "diamondCut", [cut, diamondInit, functionCall], { from: owner });

  return { diamond };
});

export default DiamondModule;
