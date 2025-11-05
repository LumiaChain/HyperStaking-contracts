import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const InvariantCheckerModule = buildModule("InvariantCheckerModule", (m) => {
  const allocationFacet = m.getParameter("allocationFacet");
  const lockboxFacet = m.getParameter("lockboxFacet");
  const hyperlaneHandlerFacet = m.getParameter("hyperlaneHandlerFacet");

  const invariantChecker = m.contract("InvariantChecker", [
    allocationFacet, lockboxFacet, hyperlaneHandlerFacet,
  ]);

  return { invariantChecker };
});

export default InvariantCheckerModule;
