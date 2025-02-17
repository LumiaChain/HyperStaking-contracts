import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "ethers";

const OneChainMailboxModule = buildModule("OneChainMailboxModule", (m) => {
  const fee = m.getParameter("fee", parseEther("0.01"));
  const localDomain = m.getParameter("localDomain", 31337);

  const mailbox = m.contract("OneChainMailbox", [fee, localDomain]);
  return { mailbox };
});

export default OneChainMailboxModule;
