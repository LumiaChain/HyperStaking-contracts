import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const GauntletStrategyModule = buildModule("GauntletStrategyModule", (m) => {
  const diamond = m.getParameter("diamond");
  const stakeToken = m.getParameter("stakeToken");
  const aeraProvisioner = m.getParameter("aeraProvisioner");

  // deploy implementation
  const impl = m.contract("GauntletStrategy", [], { id: "impl" });

  // encode initializer calldata
  const initCalldata = m.encodeFunctionCall(impl, "initialize", [
    diamond, stakeToken, aeraProvisioner,
  ]);

  // deploy ERC1967Proxy with init data
  const proxy = m.contract("ERC1967Proxy", [impl, initCalldata]);

  // treat the proxy as GauntletStrategy
  const gauntletStrategy = m.contractAt("GauntletStrategy", proxy);

  return { proxy, gauntletStrategy };
});

export default GauntletStrategyModule;
