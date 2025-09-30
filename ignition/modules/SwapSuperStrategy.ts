import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SwapSuperStrategyModule = buildModule("SwapSuperStrategyModule", (m) => {
  const diamond = m.getParameter("diamond");
  const curveInputToken = m.getParameter("curveInputToken");
  const curvePool = m.getParameter("curvePool");
  const superVault = m.getParameter("superVault");
  const superformInputToken = m.getParameter("superformInputToken");

  // deploy implementation
  const impl = m.contract("SwapSuperStrategy", [], { id: "impl" });

  // encode initializer calldata
  const fullOverloadName = "initialize(address,address,address,address,address)"; // IGN710
  const initCalldata = m.encodeFunctionCall(impl, fullOverloadName, [
    diamond, curveInputToken, curvePool, superVault, superformInputToken,
  ]);

  // deploy ERC1967Proxy with init data
  const proxy = m.contract("ERC1967Proxy", [impl, initCalldata]);

  // treat the proxy as SwapSuperStrategy
  const swapSuperStrategy = m.contractAt("SwapSuperStrategy", proxy);

  return { proxy, swapSuperStrategy };
});

export default SwapSuperStrategyModule;
