import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const ZeroYieldStrategyModule = buildModule("ZeroYieldStrategyModule", (m) => {
  const diamond = m.getParameter("diamond", "0x");
  const currencyToken = m.getParameter("currencyToken", "0x");

  const zeroYieldStrategy = m.contract("ZeroYieldStrategy", [
    diamond, { token: currencyToken },
  ]);
  return { zeroYieldStrategy };
});

export default ZeroYieldStrategyModule;
