import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "ethers";

const DEFAULT_TOKEN_SUPPLY = parseEther("21000000");

const TestERC20Module = buildModule("TestERC20Module", (m) => {
  const name = m.getParameter("name", "Test Token");
  const symbol = m.getParameter("symbol", "TT");
  const supply = m.getParameter("supply", DEFAULT_TOKEN_SUPPLY);
  const decimals = m.getParameter("decimals", 18);

  const testERC20 = m.contract("TestERC20", [name, symbol, supply, decimals]);

  return { testERC20 };
});

export default TestERC20Module;
