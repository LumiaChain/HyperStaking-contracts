import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { getSelectors, FacetCutAction } from "../../scripts/libraries/diamond";
import { getContractInterface } from "../../scripts/libraries/hardhat";

import DiamondModule from "./Diamond";

// LumiaDiamondModule is a Diamond Proxy setup for Lumia and with applied Facets
const LumiaDiamondModule = buildModule("LumiaDiamondModule", (m) => {
  const mailbox = m.getParameter("lumiaMailbox");

  const { diamond } = m.useModule(DiamondModule);

  // --- accounts

  const owner = m.getAccount(0);
  const lumiaFactoryManager = m.getAccount(4);

  // --- facets

  const interchainFactoryFacet = m.contract("InterchainFactoryFacet");
  const interchainFactoryInterface = getContractInterface("IInterchainFactory");

  const aclInterface = getContractInterface("LumiaDiamondAcl");
  const aclInterfaceSelectors = getSelectors(aclInterface).remove(["supportsInterface(bytes4)"]);

  // --- cut struct

  const cut = [
    {
      facetAddress: interchainFactoryFacet,
      action: FacetCutAction.Add,
      // acl roles are in fact applied to all potential facets
      functionSelectors: getSelectors(interchainFactoryInterface).add(aclInterfaceSelectors),
    },
  ];

  // --- cut init

  const lumiaDiamondInit = m.contract("LumiaDiamondInit");

  // _calldata A function call, including function selector and arguments,
  // _calldata is executed with delegatecall on _init
  const initCall = m.encodeFunctionCall(
    lumiaDiamondInit, "init", [mailbox],
  );

  const diamondCut = m.contractAt("IDiamondCut", diamond);
  const diamondCutFuture = m.call(
    diamondCut, "diamondCut", [cut, lumiaDiamondInit, initCall], { from: owner },
  );

  // --- grant roles

  const acl = m.contractAt("LumiaDiamondAcl", diamond);
  const LUMIA_FACTORY_MANAGER_ROLE = m.staticCall(acl, "LUMIA_FACTORY_MANAGER_ROLE", [], 0);

  m.call(
    acl,
    "grantRole",
    [LUMIA_FACTORY_MANAGER_ROLE, lumiaFactoryManager],
    { id: "grantRoleFactoryManager", after: [diamondCutFuture] },
  );

  // --- init facets

  const interchainFactory = m.contractAt("IInterchainFactory", diamond);

  // --- return

  return { lumiaDiamond: diamond, interchainFactory };
});

export default LumiaDiamondModule;
