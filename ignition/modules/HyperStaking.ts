import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { getSelectors, FacetCutAction } from "../../scripts/libraries/diamond";
import { getContractInterface } from "../../scripts/libraries/hardhat";

import DiamondModule from "./Diamond";

// HyperStakingModule is in fact a proxy upgrade which adds the Facets to the Diamond
const HyperStakingModule = buildModule("HyperStakingModule", (m) => {
  const mailbox = m.getParameter("lockboxMailbox");
  const destination = m.getParameter("lockboxDestination");
  const superformFactory = m.getParameter("superformFactory");
  const superformRouter = m.getParameter("superformRouter");
  const superPositions = m.getParameter("superPositions");

  const { diamond } = m.useModule(DiamondModule);

  // --- accounts

  const owner = m.getAccount(0);
  const stakingManager = m.getAccount(1);
  const strategyVaultManager = m.getAccount(2);

  // --- facets

  const stakingFacet = m.contract("StakingFacet");
  const stakingFacetInterface = getContractInterface("IStaking");

  const vaultFactoryFacet = m.contract("VaultFactoryFacet");
  const vaultFactoryFacetInterface = getContractInterface("IVaultFactory");

  const tier1Facet = m.contract("Tier1VaultFacet");
  const tier1FacetInterface = getContractInterface("ITier1Vault");

  const tier2Facet = m.contract("Tier2VaultFacet");
  const tier2FacetInterface = getContractInterface("ITier2Vault");

  const lockboxFacet = m.contract("LockboxFacet");
  const lockboxFacetInterface = getContractInterface("ILockbox");

  const aclInterface = getContractInterface("HyperStakingAcl");
  const aclInterfaceSelectors = getSelectors(aclInterface).remove(["supportsInterface(bytes4)"]);

  // --- cut struct

  const cut = [
    {
      facetAddress: stakingFacet,
      action: FacetCutAction.Add,
      // acl roles are applied to all facets, staking facet is used here with no reason
      functionSelectors: getSelectors(stakingFacetInterface).add(aclInterfaceSelectors),
    },
    {
      facetAddress: vaultFactoryFacet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(vaultFactoryFacetInterface),
    },
    {
      facetAddress: tier1Facet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(tier1FacetInterface),
    },
    {
      facetAddress: tier2Facet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(tier2FacetInterface),
    },
    {
      facetAddress: lockboxFacet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(lockboxFacetInterface),
    },
  ];

  // --- cut init

  const hyperStakingInit = m.contract("HyperStakingInit");
  const initCall = m.encodeFunctionCall(
    hyperStakingInit, "init", [
      stakingManager,
      strategyVaultManager,
      mailbox,
      destination,
      superformFactory,
      superformRouter,
      superPositions,
    ],
  );

  const diamondCut = m.contractAt("IDiamondCut", diamond);
  m.call(
    diamondCut, "diamondCut", [cut, hyperStakingInit, initCall], { from: owner },
  );

  // --- init facets

  const acl = m.contractAt("HyperStakingAcl", diamond);
  const staking = m.contractAt("IStaking", diamond);
  const factory = m.contractAt("IVaultFactory", diamond);
  const tier1 = m.contractAt("ITier1Vault", diamond);
  const tier2 = m.contractAt("ITier2Vault", diamond);
  const lockbox = m.contractAt("ILockbox", diamond);

  // --- return

  return { diamond, acl, staking, factory, tier1, tier2, lockbox };
});

export default HyperStakingModule;
