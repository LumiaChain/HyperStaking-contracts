import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ZeroAddress } from "ethers";

const LumiaXERC20Module = buildModule("LumiaXERC20Module", (m) => {
  const mailbox = m.getParameter("mailbox", ZeroAddress);
  const name = m.getParameter("name", "Test xToken");
  const symbol = m.getParameter("symbol", "TxT");

  const xERC20 = m.contract("LumiaXERC20", [mailbox, name, symbol]);
  return { xERC20 };
});

export default LumiaXERC20Module;
