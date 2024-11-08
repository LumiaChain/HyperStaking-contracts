import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { getSelectors, FacetCutAction } from "../../scripts/libraries/diamond";
import { getContractInterface } from "../../scripts/libraries/hardhat";

import DiamondModule from "./Diamond";

// HyperStakingModule is in fact a proxy upgrade which adds the Facets to the Diamond
const HyperStakingModule = buildModule("HyperStakingModule", (m) => {
  const { diamond } = m.useModule(DiamondModule);

  // --- accounts

  const owner = m.getAccount(0);
  const stakingManager = m.getAccount(1);
  const strategyVaultManager = m.getAccount(2);

  // --- facets

  const stakingFacet = m.contract("StakingFacet");
  const stakingFacetInterface = getContractInterface("IStaking");

  const vaultFacet = m.contract("StrategyVaultFacet");
  const vaultFacetInterface = getContractInterface("IStrategyVault");

  const tier1Facet = m.contract("Tier1VaultFacet");
  const tier1FacetInterface = getContractInterface("ITier1Vault");

  const tier2Facet = m.contract("Tier2VaultFacet");
  const tier2FacetInterface = getContractInterface("ITier2Vault");

  const aclInterface = getContractInterface("HyperStakingAcl");
  const aclInterfaceSelectors = getSelectors(aclInterface).remove(["supportsInterface(bytes4)"]);
  ;

  // --- cut struct

  const cut = [
    {
      facetAddress: stakingFacet,
      action: FacetCutAction.Add,
      // acl roles are applied to all facets, staking facet is used here with no reason
      functionSelectors: getSelectors(stakingFacetInterface).add(aclInterfaceSelectors),
    },
    {
      facetAddress: vaultFacet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(vaultFacetInterface),
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
  ];

  // --- cut init

  const hyperStakingInit = m.contract("HyperStakingInit");
  const hyperStakingInitInterface = getContractInterface("HyperStakingInit");
  const initCall = hyperStakingInitInterface.encodeFunctionData("init");

  const diamondCut = m.contractAt("IDiamondCut", diamond);
  m.call(diamondCut, "diamondCut", [cut, hyperStakingInit, initCall], { from: owner });

  // --- init facets

  const staking = m.contractAt("IStaking", diamond);
  const vault = m.contractAt("IStrategyVault", diamond);
  const tier1 = m.contractAt("ITier1Vault", diamond);
  const tier2 = m.contractAt("ITier2Vault", diamond);

  const roles = m.contractAt("IHyperStakingRoles", diamond);
  const acl = m.contractAt("HyperStakingAcl", diamond);

  // --- grant roles

  const STAKING_MANAGER_ROLE = m.staticCall(roles, "STAKING_MANAGER_ROLE", []);
  const STRATEGY_VAULT_MANAGER_ROLE = m.staticCall(roles, "STRATEGY_VAULT_MANAGER_ROLE", []);

  m.call(
    acl,
    "grantRole",
    [STAKING_MANAGER_ROLE, stakingManager],
    { id: "grantRoleStakingManager" },
  );

  m.call(
    acl,
    "grantRole",
    [STRATEGY_VAULT_MANAGER_ROLE, strategyVaultManager],
    { id: "grantRoleStrategyVaultManager" },
  );

  // --- return

  return { diamond, staking, vault, tier1, tier2 };
});

export default HyperStakingModule;
