import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Deploys a test Curve Router, a mock used for tests
const CurveMockModule = buildModule("CurveMockModule", (m) => {
  const usdcAddress = m.getParameter("usdcAddress");
  const usdtAddress = m.getParameter("usdtAddress");

  const curvePool = m.contract("MockCurvePool", [usdcAddress, usdtAddress]);
  const curveRouter = m.contract("MockCurveRouter", []);

  return { curvePool, curveRouter };
});

export default CurveMockModule;
