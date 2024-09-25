import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { getSelectors, FacetCutAction } from "../../scripts//libraries/diamond";
import { getContractInterface } from "../../scripts//libraries/hardhat";
import { ZeroAddress } from "ethers";
import DiamondModule from "./Diamond";

// HyperStakingModule is in fact a proxy upgrade which adds the Facets to the Diamond
const HyperStakingModule = buildModule("HyperStakingModule", (m) => {
  const { diamond } = m.useModule(DiamondModule);

  const stakingFacet = m.contract("StakingFacet");
  const stakingFacetInterface = getContractInterface("IStaking");

  const vaultFacet = m.contract("StrategyVaultFacet");
  const vaultFacetInterface = getContractInterface("IStrategyVault");

  // cut StakingFacet
  const cut = [
    {
      facetAddress: stakingFacet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(stakingFacetInterface),
    },
    {
      facetAddress: vaultFacet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(vaultFacetInterface),
    },
  ];

  const owner = m.getAccount(0); // ZeroAddress for init function

  const diamondCut = m.contractAt("IDiamondCut", diamond);
  m.call(diamondCut, "diamondCut", [cut, ZeroAddress, "0x"], { from: owner });

  return { diamond };
});

export default HyperStakingModule;
