import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const DIAMOND_ADDRESS = "0x";

const PX_ETH_ADDRESS = "0x";
const PIREX_ETH_ADDRESS = "0x";
const AUTO_PX_ETH_ADDRESS = "0x";

const DineroStrategyModule = buildModule("DineroStrategyModule", (m) => {
  const diamond = m.getParameter("diamond", DIAMOND_ADDRESS);
  const pxEth = m.getParameter("pxEth", PX_ETH_ADDRESS);
  const pirexEth = m.getParameter("pirexEth", PIREX_ETH_ADDRESS);
  const autoPxEth = m.getParameter("autoPxEth", AUTO_PX_ETH_ADDRESS);

  // deploy implementation
  const impl = m.contract("DineroStrategy", [], { id: "impl" });

  // encode initializer calldata
  const initCalldata = m.encodeFunctionCall(impl, "initialize", [
    diamond, pxEth, pirexEth, autoPxEth,
  ]);

  // deploy ERC1967Proxy with init data
  const proxy = m.contract("ERC1967Proxy", [impl, initCalldata]);

  // treat the proxy as DineroStrategy
  const dineroStrategy = m.contractAt("DineroStrategy", proxy);

  return { proxy, dineroStrategy };
});

export default DineroStrategyModule;
