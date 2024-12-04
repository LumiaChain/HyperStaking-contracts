import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const LumiaXERC20Module = buildModule("LumiaXERC20Module", (m) => {
  const name = m.getParameter("name", "Test xToken");
  const symbol = m.getParameter("symbol", "TxT");

  const xERC20 = m.contract("LumiaXERC20", [name, symbol]);
  return { xERC20 };
});

export default LumiaXERC20Module;
