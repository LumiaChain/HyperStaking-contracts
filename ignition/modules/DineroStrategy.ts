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

  const dineroStrategy = m.contract("DineroStrategy", [diamond, pxEth, pirexEth, autoPxEth]);

  return { dineroStrategy };
});

export default DineroStrategyModule;
