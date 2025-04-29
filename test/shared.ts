import { ignition, ethers, network } from "hardhat";
import { Contract, ZeroAddress, parseEther } from "ethers";

import HyperStakingModule from "../ignition/modules/HyperStaking";
import LumiaDiamondModule from "../ignition/modules/LumiaDiamond";
import OneChainMailboxModule from "../ignition/modules/test/OneChainMailbox";
import SuperformMockModule from "../ignition/modules/test/SuperformMock";

import TestERC20Module from "../ignition/modules/test/TestERC20";
import ReserveStrategyModule from "../ignition/modules/ReserveStrategy";
import ZeroYieldStrategyModule from "../ignition/modules/ZeroYieldStrategy";
import DirectStakeStrategyModule from "../ignition/modules/DirectStakeStrategy";

import { CurrencyStruct } from "../typechain-types/contracts/hyperstaking/interfaces/IHyperFactory";
import { IERC20 } from "../typechain-types";

// full - because there are two differnet vesions of IERC20 used in the project
const fullyQualifiedIERC20 = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

// -------------------- Accounts --------------------

export async function getSigners() {
  const [
    owner, stakingManager, vaultManager, strategyManager, lumiaFactoryManager, bob, alice,
  ] = await ethers.getSigners();

  return { owner, stakingManager, vaultManager, strategyManager, lumiaFactoryManager, bob, alice };
}

// -------------------- Currency --------------------

export const nativeTokenAddress = ZeroAddress;

export function nativeCurrency(): CurrencyStruct {
  return { token: nativeTokenAddress };
}

/// token contract address
export function erc20Currency(token: string): CurrencyStruct {
  return { token };
}

// -------------------- Deployment Helpers --------------------

export async function deploySuperformMock(erc4626Vault: Contract) {
  const testUSDC = await ethers.getContractAt(fullyQualifiedIERC20, await erc4626Vault.asset());

  // --- set TokenizedStrategy code on a given address ---

  const factory = await ethers.getContractFactory("TokenizedStrategy");
  const instance = await factory.deploy(testUSDC);

  const deployedBytecode = await ethers.provider.getCode(await instance.getAddress());

  await network.provider.send("hardhat_setCode", [
    "0xBB51273D6c746910C7C06fe718f30c936170feD0",
    deployedBytecode,
  ]);

  // -------------------- Superform Mock --------------------

  return ignition.deploy(SuperformMockModule, {
    parameters: {
      SuperformMockModule: {
        erc4626VaultAddress: await erc4626Vault.getAddress(),
      },
    },
  });
}

export async function deployTestHyperStaking(mailboxFee: bigint, erc4626Vault: Contract) {
  const testDestination = 31337; // the same for both sides of the test "oneChain" bridge

  const { mailbox } = await ignition.deploy(OneChainMailboxModule, {
    parameters: {
      OneChainMailboxModule: {
        fee: mailboxFee,
        localDomain: testDestination,
      },
    },
  });
  const mailboxAddress = await mailbox.getAddress();

  const {
    superformFactory, superformRouter, superVault, superPositions,
  } = await deploySuperformMock(erc4626Vault);

  const { diamond, deposit, hyperFactory, stakeVault, lockbox, routeRegistry, stakeInfoRoute, superformIntegration } = await ignition.deploy(HyperStakingModule, {
    parameters: {
      HyperStakingModule: {
        lockboxMailbox: mailboxAddress,
        lockboxDestination: testDestination,
        superformFactory: await superformFactory.getAddress(),
        superformRouter: await superformRouter.getAddress(),
        superPositions: await superPositions.getAddress(),
      },
    },
  });

  const { lumiaDiamond, hyperlaneHandler, realAssets } = await ignition.deploy(LumiaDiamondModule, {
    parameters: {
      LumiaDiamondModule: {
        lumiaMailbox: mailboxAddress,
      },
    },
  });

  const { vaultManager, lumiaFactoryManager } = await getSigners();

  // finish setup for hyperstaking
  await lockbox.connect(vaultManager).setLumiaFactory(hyperlaneHandler);

  // finish setup for lumia diamond
  const authorized = true;
  await hyperlaneHandler.connect(lumiaFactoryManager).updateAuthorizedOrigin(
    lockbox,
    authorized,
    testDestination,
  );

  return {
    mailbox, hyperlaneHandler, diamond, deposit, hyperFactory, stakeVault, lockbox, routeRegistry, stakeInfoRoute, superformFactory, superVault, superformIntegration, lumiaDiamond, realAssets,
  };
}

export async function deloyTestERC20(name: string, symbol: string, decimals: number = 18): Promise<Contract> {
  const { testERC20 } = await ignition.deploy(TestERC20Module, {
    parameters: {
      TestERC20Module: {
        name,
        symbol,
        decimals,
      },
    },
  });
  return testERC20;
}

export async function deloyTestERC4626Vault(asset: Contract): Promise<Contract> {
  return ethers.deployContract("TestERC4626", [await asset.getAddress()]) as unknown as Promise<Contract>;
}

// -------------------- Strategies --------------------

/// ZeroAddress is used for native currency
export async function createReserveStrategy(
  diamond: Contract,
  stakeTokenAddress: string,
  assetAddress: string,
  assetPrice: bigint,
) {
  const { reserveStrategy } = await ignition.deploy(ReserveStrategyModule, {
    parameters: {
      ReserveStrategyModule: {
        diamond: await diamond.getAddress(),
        stake: stakeTokenAddress,
        asset: assetAddress,
        assetPrice,
      },
    },
  });

  const { owner, strategyManager } = await getSigners();

  const reserveStrategySupply = parseEther("50");

  const asset = (await ethers.getContractAt(fullyQualifiedIERC20, assetAddress)) as unknown as IERC20;

  await asset.transfer(strategyManager, reserveStrategySupply); // owner -> strategyManager
  await asset.connect(strategyManager).approve(reserveStrategy.target, reserveStrategySupply);

  await reserveStrategy.connect(strategyManager).supplyRevenueAsset(reserveStrategySupply);

  await owner.sendTransaction({
    to: reserveStrategy,
    value: reserveStrategySupply,
  });

  return reserveStrategy;
}

/// @param currencyToken ZeroAddress is used for native currency
export async function createZeroYieldStrategy(
  diamond: Contract,
  currencyToken: string,
) {
  const { zeroYieldStrategy } = await ignition.deploy(ZeroYieldStrategyModule, {
    parameters: {
      ZeroYieldStrategyModule: {
        diamond: await diamond.getAddress(),
        currencyToken,
      },
    },
  });

  return zeroYieldStrategy;
}

export async function createDirectStakeStrategy(
  diamond: Contract,
  currencyToken: string,
) {
  const { directStakeStrategy } = await ignition.deploy(DirectStakeStrategyModule, {
    parameters: {
      DirectStakeStrategyModule: {
        diamond: await diamond.getAddress(),
        currencyToken,
      },
    },
  });

  return directStakeStrategy;
}

// -------------------- Other Helpers --------------------

export async function getDerivedTokens(stakeVault: Contract, routeFactory: Contract, strategy: string) {
  const vaultTokenAddress = (await stakeVault.stakeInfo(strategy)).vaultToken;
  const vaultToken = await ethers.getContractAt("VaultToken", vaultTokenAddress);

  const lpTokenAddress = await routeFactory.getLpToken(strategy);
  const lpToken = await ethers.getContractAt("LumiaLPToken", lpTokenAddress);

  return { vaultToken, lpToken };
}

export async function getCurrentBlockTimestamp() {
  const blockNumber = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blockNumber);
  return block!.timestamp;
}
