import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const DirectStakeStrategyModule = buildModule("DirectStakeStrategyModule", (m) => {
  const diamond = m.getParameter("diamond", "0x");
  const currencyToken = m.getParameter("currencyToken", "0x");

  const directStakeStrategy = m.contract("DirectStakeStrategy", [
    diamond, { token: currencyToken },
  ]);
  return { directStakeStrategy };
});

export default DirectStakeStrategyModule;
