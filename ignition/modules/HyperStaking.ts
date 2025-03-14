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
  const vaultManager = m.getAccount(2);
  const strategyManager = m.getAccount(3);

  // --- facets

  const aclInterface = getContractInterface("HyperStakingAcl");
  const aclInterfaceSelectors = getSelectors(aclInterface).remove(["supportsInterface(bytes4)"]);

  const depositFacet = m.contract("DepositFacet");
  const depositFacetInterface = getContractInterface("IDeposit");

  const hyperFactoryFacet = m.contract("HyperFactoryFacet");
  const hyperFactoryFacetInterface = getContractInterface("IHyperFactory");

  const tier1Facet = m.contract("Tier1VaultFacet");
  const tier1FacetInterface = getContractInterface("ITier1Vault");

  const tier2Facet = m.contract("Tier2VaultFacet");
  const tier2FacetInterface = getContractInterface("ITier2Vault");

  const lockboxFacet = m.contract("LockboxFacet");
  const lockboxFacetInterface = getContractInterface("ILockbox");

  const migrationFacet = m.contract("MigrationFacet");
  const migrationFacetInterface = getContractInterface("IMigration");

  const superformIntegrationFacet = m.contract("SuperformIntegrationFacet");
  const superformIntegrationFacetInterface = getContractInterface("ISuperformIntegration");
  const superformIntegrationFacetSelectors = getSelectors(superformIntegrationFacetInterface)
    .remove(["supportsInterface(bytes4)"]);

  // --- cut struct

  const cut = [
    {
      facetAddress: depositFacet,
      action: FacetCutAction.Add,
      // acl roles are applied to all facets, deposit facet is used here with no reason
      functionSelectors: getSelectors(depositFacetInterface).add(aclInterfaceSelectors),
    },
    {
      facetAddress: hyperFactoryFacet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(hyperFactoryFacetInterface),
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
    {
      facetAddress: migrationFacet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(migrationFacetInterface),
    },
    {
      facetAddress: superformIntegrationFacet,
      action: FacetCutAction.Add,
      functionSelectors: superformIntegrationFacetSelectors,
    },
  ];

  // --- cut init

  const hyperStakingInit = m.contract("HyperStakingInit");
  const initCall = m.encodeFunctionCall(
    hyperStakingInit, "init", [
      stakingManager,
      vaultManager,
      strategyManager,
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
  const deposit = m.contractAt("IDeposit", diamond);
  const hyperFactory = m.contractAt("IHyperFactory", diamond);
  const tier1 = m.contractAt("ITier1Vault", diamond);
  const tier2 = m.contractAt("ITier2Vault", diamond);
  const lockbox = m.contractAt("ILockbox", diamond);
  const migration = m.contractAt("IMigration", diamond);
  const superformIntegration = m.contractAt("ISuperformIntegration", diamond);

  // --- return

  return {
    diamond, acl, deposit, hyperFactory, tier1, tier2, lockbox, migration, superformIntegration,
  };
});

export default HyperStakingModule;
