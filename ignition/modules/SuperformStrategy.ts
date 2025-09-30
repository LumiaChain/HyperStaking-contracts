import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SuperformStrategyModule = buildModule("SuperformStrategyModule", (m) => {
  const diamond = m.getParameter("diamond");
  const superVault = m.getParameter("superVault");
  const stakeToken = m.getParameter("stakeToken");

  // deploy implementation
  const impl = m.contract("SuperformStrategy", [], { id: "impl" });

  // encode initializer calldata
  const initCalldata = m.encodeFunctionCall(impl, "initialize", [
    diamond, superVault, stakeToken,
  ]);

  // deploy ERC1967Proxy with init data
  const proxy = m.contract("ERC1967Proxy", [impl, initCalldata]);

  // treat the proxy as SuperformStrategy
  const superformStrategy = m.contractAt("SuperformStrategy", proxy);

  return { proxy, superformStrategy };
});

export default SuperformStrategyModule;
