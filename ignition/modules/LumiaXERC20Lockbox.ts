import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const LumiaXERC20Module = buildModule("LumiaXERC20Module", (m) => {
  const erc20Address = m.getParameter("erc20Address");
  const xerc20Address = m.getParameter("xerc20Address");
  const native = m.getParameter("native", false);

  const xERC20Lockbox = m.contract("LumiaXERC20Lockbox", [erc20Address, xerc20Address, native]);

  return { xERC20Lockbox };
});

export default LumiaXERC20Module;
