import hre from "hardhat";
import { parseEther, Signer } from "ethers";
import { deployContractVerbose } from "./libraries/hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { LumiaXERC20Lockbox, LumiaXERC20, LumiaReceiver } from "../typechain-types";

// origin token to bridge
const ERC20_TOKEN_CHAIN_A = "";
const BROKER = "";

// A - source chain, B - destination chain
const CHAIN_A = "holesky";
const CHAIN_B = "lumia_testnet";

const MAILBOX = {
  holesky: "0x46f7C5D896bbeC89bE1B19e4485e59b4Be49e9Cc",
  bsc_testnet: "0xF9F6F5646F478d5ab4e20B0F910C92F1CCC9Cc6D",
  lumia_testnet: "0xCE6babAFd498E0f225D0C3cABD18cbC5210D8D94",
};

type ChainADeployment = {
  xerc20?: LumiaXERC20;
  lockbox?: LumiaXERC20Lockbox;
};

type ChainBDeployment = {
  xerc20?: LumiaXERC20;
  lumiaReceiver?: LumiaReceiver;
};

async function main(hre: HardhatRuntimeEnvironment) {
  const xERC20Name = "TokenB";
  const xERC20Symbol = "tB";

  const ChainA: ChainADeployment = {};
  const ChainB: ChainBDeployment = {};

  let deployer: Signer;
  const getDeployer = async (hre: HardhatRuntimeEnvironment) => {
    // use first hardhat account (for a given network) as deployer
    return (await hre.ethers.getSigners())[0];
  };

  // ------------------- deploy xerc20 and lockbox on CHAIN_A

  await hre.switchNetwork(CHAIN_A);
  deployer = await getDeployer(hre);

  const destination = hre.config.networks[CHAIN_B].chainId; // use chain B chainId

  ChainA.xerc20 = await deployContractVerbose<LumiaXERC20>(
    deployer,
    "LumiaXERC20",
    [MAILBOX[CHAIN_A], xERC20Name, xERC20Symbol],
  );

  ChainA.lockbox = await deployContractVerbose<LumiaXERC20Lockbox>(
    deployer,
    "LumiaXERC20Lockbox",
    [MAILBOX[CHAIN_A], destination, ERC20_TOKEN_CHAIN_A, ChainA.xerc20!.target],
  );

  // ------------------- deploy xerc20 and lumiaReceiver on CHAIN_B

  await hre.switchNetwork(CHAIN_B);
  deployer = await getDeployer(hre);

  ChainB.xerc20 = await deployContractVerbose<LumiaXERC20>(
    deployer,
    "LumiaXERC20",
    [MAILBOX[CHAIN_B], xERC20Name, xERC20Symbol],
  );

  ChainB.lumiaReceiver = await deployContractVerbose<LumiaReceiver>(
    deployer,
    "LumiaReceiver",
    [],
  );

  // ------------------- setup CHAIN_A

  await hre.switchNetwork(CHAIN_A);

  console.log(`[${CHAIN_A}] Setting lockbox target`);
  let tx = await ChainA.xerc20!.setLockbox(ChainA.lockbox!.target);
  await tx.wait();

  console.log(`[${CHAIN_A}] Setting lockbox recipient`);
  tx = await ChainA.lockbox!.setRecipient(ChainA.xerc20!.target);
  await tx.wait();

  // ------------------- setup CHAIN_B

  await hre.switchNetwork(CHAIN_B);

  const mintingLimit = parseEther("1000000");
  const burningLimit = parseEther("1000000");

  console.log(`[${CHAIN_B}] Setting limits`);
  tx = await ChainB.xerc20!.setLimits(ChainB.lumiaReceiver!.target, mintingLimit, burningLimit);
  await tx.wait();

  console.log(`[${CHAIN_B}] Setting origin lockbox`);
  tx = await ChainB.xerc20!.setOriginLockbox(ChainA.lockbox!.target);
  await tx.wait();

  console.log(`[${CHAIN_B}] Setting lumia receiver`);
  tx = await ChainB.xerc20!.setLumiaReceiver(ChainB.lumiaReceiver!.target);
  await tx.wait();

  console.log(`[${CHAIN_B}] Updating registered token`);
  tx = await ChainB.lumiaReceiver!.updateRegisteredToken(ChainB.xerc20!.target, true);
  await tx.wait();

  console.log(`[${CHAIN_B}] Setting broker`);
  tx = await ChainB.lumiaReceiver!.setBroker(BROKER);
  await tx.wait();
}

main(hre).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
