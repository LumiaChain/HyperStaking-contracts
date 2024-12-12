import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "ethers";

const OneChainMailboxModule = buildModule("OneChainMailboxModule", (m) => {
  const fee = m.getParameter("fee", parseEther("0.01"));

  const mailbox = m.contract("OneChainMailbox", [fee]);
  return { mailbox };
});

export default OneChainMailboxModule;
