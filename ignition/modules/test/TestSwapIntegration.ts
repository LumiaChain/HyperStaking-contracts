import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TestSwapIntegrationModule = buildModule("TestSwapIntegrationModule", (m) => {
  const superformFactory = m.getParameter("superformFactory");
  const superformRouter = m.getParameter("superformRouter");
  const superPositions = m.getParameter("superPositions");
  const curveRouter = m.getParameter("curveRouter");

  const testSwapIntegration = m.contract("TestSwapIntegration");

  const strategyManager = m.getAccount(0);

  m.call(testSwapIntegration, "initialize", [
    superformFactory,
    superformRouter,
    superPositions,
    curveRouter,
    strategyManager,
  ]);

  return { testSwapIntegration };
});

export default TestSwapIntegrationModule;
