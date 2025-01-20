import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SuperformStrategyModule = buildModule("SuperformStrategyModule", (m) => {
  const diamond = m.getParameter("diamond");
  const superformId = m.getParameter("superformId");
  const stakeToken = m.getParameter("stakeToken");

  const superformStrategy = m.contract("SuperformStrategy", [diamond, superformId, stakeToken]);

  return { superformStrategy };
});

export default SuperformStrategyModule;
