import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SuperformStrategyModule = buildModule("SuperformStrategyModule", (m) => {
  const diamond = m.getParameter("diamond");
  const superVault = m.getParameter("superVault");
  const stakeToken = m.getParameter("stakeToken");

  const superformStrategy = m.contract("SuperformStrategy", [diamond, superVault, stakeToken]);

  return { superformStrategy };
});

export default SuperformStrategyModule;
