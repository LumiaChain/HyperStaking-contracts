import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const RevertingContractModule = buildModule("RevertingContractModule", (m) => {
  const revertingContract = m.contract("RevertingContract");
  return { revertingContract };
});

export default RevertingContractModule;
