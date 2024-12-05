import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const OneChainMailboxModule = buildModule("OneChainMailboxModule", (m) => {
  const mailbox = m.contract("OneChainMailbox", []);
  return { mailbox };
});

export default OneChainMailboxModule;
