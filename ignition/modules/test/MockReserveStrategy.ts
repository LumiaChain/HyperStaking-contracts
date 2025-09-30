import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "ethers";

const ReserveStrategyModule = buildModule("ReserveStrategyModule", (m) => {
  const diamond = m.getParameter("diamond", "0x");
  const stake = m.getParameter("stake", "0x");
  const asset = m.getParameter("asset", "0x");
  const assetPrice = m.getParameter("assetPrice", parseEther("1"));

  const impl = m.contract("MockReserveStrategy", [], { id: "impl" });
  const proxy = m.contract("ERC1967Proxy", [impl, "0x"]);

  const reserveStrategy = m.contractAt("MockReserveStrategy", proxy);

  // Initialize via the proxy
  m.call(reserveStrategy, "initialize", [
    diamond,
    { token: stake },
    asset,
    assetPrice,
  ]);

  return { proxy, reserveStrategy };
});

export default ReserveStrategyModule;
