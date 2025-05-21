import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const SwapSuperStrategyModule = buildModule("SwapSuperStrategyModule", (m) => {
  const diamond = m.getParameter("diamond");
  const curveInputToken = m.getParameter("curveInputToken");
  const curvePool = m.getParameter("curvePool");
  const superVault = m.getParameter("superVault");
  const superformInputToken = m.getParameter("superformInputToken");

  const swapSuperStrategy = m.contract("SwapSuperStrategy", [
    diamond, curveInputToken, curvePool, superVault, superformInputToken,
  ]);

  return { swapSuperStrategy };
});

export default SwapSuperStrategyModule;
