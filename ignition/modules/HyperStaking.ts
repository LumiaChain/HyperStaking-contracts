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
  const rewardsManager = m.getAccount(3);

  // --- facets

  const stakingFacet = m.contract("StakingFacet");
  const stakingFacetInterface = getContractInterface("IStaking");

  const vaultFacet = m.contract("StrategyVaultFacet");
  const vaultFacetInterface = getContractInterface("IStrategyVault");

  const rewarderFacet = m.contract("RewarderFacet");
  const rewarderFacetInterface = getContractInterface("IRewarder");

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
      facetAddress: rewarderFacet,
      action: FacetCutAction.Add,
      functionSelectors: getSelectors(rewarderFacetInterface),
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
  const rewarder = m.contractAt("IRewarder", diamond);

  const roles = m.contractAt("IHyperStakingRoles", diamond);
  const acl = m.contractAt("HyperStakingAcl", diamond);

  // --- grant roles

  const STAKING_MANAGER_ROLE = m.staticCall(roles, "STAKING_MANAGER_ROLE", []);
  const STRATEGY_VAULT_MANAGER_ROLE = m.staticCall(roles, "STRATEGY_VAULT_MANAGER_ROLE", []);
  const REWARDS_MANAGER_ROLE = m.staticCall(roles, "REWARDS_MANAGER_ROLE", []);

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

  m.call(
    acl,
    "grantRole",
    [REWARDS_MANAGER_ROLE, rewardsManager],
    { id: "grantRoleRewardsManager" },
  );

  // --- return

  return { diamond, staking, vault, rewarder };
});

export default HyperStakingModule;
