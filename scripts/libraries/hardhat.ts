import { ethers, artifacts } from "hardhat";
import { Interface, Signer, ContractTransactionResponse, ContractTransactionReceipt } from "ethers";

export function getContractInterface(contractName: string): Interface {
  const contractArtifacts = artifacts.readArtifactSync(contractName);
  return new Interface(contractArtifacts.abi);
}

export async function deployContract<ContractType>(
  deployer: Signer,
  contractName: string,
  args: any[], // eslint-disable-line @typescript-eslint/no-explicit-any
): Promise<{ contract: ContractType; receipt: ContractTransactionReceipt; }> {
  const confirmations = 1;
  const factory = await ethers.getContractFactory(contractName, deployer);

  // call the deploy function
  const deployedContract = await factory.deploy(
    ...args,
    { from: deployer }, // repeat the signer
  );

  // access contract instance and transaction details
  const contractInstance = deployedContract as unknown as ContractType & {
    deploymentTransaction(): ContractTransactionResponse;
  };

  const tx = contractInstance.deploymentTransaction();
  const receipt = await tx.wait(confirmations);

  if (!receipt) {
    throw new Error(`Contract deployment failed: ${contractName}`);
  }

  return { contract: contractInstance, receipt };
}
