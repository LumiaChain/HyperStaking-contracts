import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const GauntletStrategyModule = buildModule("GauntletStrategyModule", (m) => {
  const diamond = m.getParameter("diamond");
  const stakeToken = m.getParameter("stakeToken");
  const aeraProvisioner = m.getParameter("aeraProvisioner");

  const gauntletStrategy = m.contract("GauntletStrategy", [
    diamond, stakeToken, aeraProvisioner,
  ]);

  return { gauntletStrategy };
});

export default GauntletStrategyModule;
