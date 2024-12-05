import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const LumiaReceiverModule = buildModule("LumiaReceiverModule", (m) => {
  const lumiaReceiver = m.contract("LumiaReceiver", []);
  return { lumiaReceiver };
});

export default LumiaReceiverModule;
