import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const LumiaXERC20LockboxModule = buildModule("LumiaXERC20LockboxModule", (m) => {
  const mailbox = m.getParameter("mailbox");
  const destination = m.getParameter("destination");

  const xerc20Address = m.getParameter("xerc20Address");
  const erc20Address = m.getParameter("erc20Address");
  const native = m.getParameter("native", false);

  const xERC20Lockbox = m.contract("LumiaXERC20Lockbox", [
    mailbox,
    destination,
    xerc20Address,
    erc20Address,
    native,
  ]);

  return { xERC20Lockbox };
});

export default LumiaXERC20LockboxModule;
