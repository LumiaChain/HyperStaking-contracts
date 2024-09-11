import { artifacts } from "hardhat";
import { ethers, Interface } from "ethers";

export function getContractInterface(contractName: string): Interface {
  const contractArtifacts = artifacts.readArtifactSync(contractName);
  return new ethers.Interface(contractArtifacts.abi);
}
