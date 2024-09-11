import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { getSelectors, FacetCutAction } from "../../scripts//libraries/diamond";
import { getContractInterface } from "../../scripts//libraries/hardhat";

import { ZeroAddress } from "ethers";

import DiamondModule from "./Diamond";

// HyperStakingModule is in fact a proxy upgrade which adds the StakingFacet to the Diamond
const HyperStakingModule = buildModule("HyperStakingModule", (m) => {
  const { diamond } = m.useModule(DiamondModule);

  const stakingFacet = m.contract("StakingFacet");
  const diamondCut = m.contractAt("IDiamondCut", diamond);

  // needed to get the function selectors
  const stakingFacetInterface = getContractInterface("StakingFacet");

  // cut StakingFacet
  const cut = [
    {
      facetAddress: stakingFacet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(stakingFacetInterface),
    },
  ];

  // ZeroAddress for init function
  const owner = m.getAccount(0);
  m.call(diamondCut, "diamondCut", [cut, ZeroAddress, "0x"], { from: owner });

  return { diamond };
});

export default HyperStakingModule;
