import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const DirectStakeStrategyModule = buildModule("DirectStakeStrategyModule", (m) => {
  const diamond = m.getParameter("diamond", "0x");
  const currencyToken = m.getParameter("currencyToken", "0x");

  // deploy implementation
  const impl = m.contract("DirectStakeStrategy", [], { id: "impl" });

  // encode initializer calldata
  const initCalldata = m.encodeFunctionCall(impl, "initialize", [
    diamond, { token: currencyToken },
  ]);

  // deploy ERC1967Proxy with init data
  const proxy = m.contract("ERC1967Proxy", [impl, initCalldata]);

  // treat the proxy as DirectStakeStrategy
  const directStakeStrategy = m.contractAt("DirectStakeStrategy", proxy);

  return { proxy, directStakeStrategy };
});

export default DirectStakeStrategyModule;
