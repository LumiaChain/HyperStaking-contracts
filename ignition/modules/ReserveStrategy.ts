import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "ethers";

const ReserveStrategyModule = buildModule("ReserveStrategyModule", (m) => {
  const diamond = m.getParameter("diamond", "0x");
  const asset = m.getParameter("asset", "0x");
  const assetPrice = m.getParameter("assetPrice", parseEther("1"));

  const reserveStrategy = m.contract("ReserveStrategy", [diamond, asset, assetPrice]);
  return { reserveStrategy };
});

export default ReserveStrategyModule;
