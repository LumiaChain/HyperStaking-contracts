import { ignition, ethers } from "hardhat";
import { Contract, ZeroAddress, parseEther } from "ethers";

import HyperStakingModule from "../ignition/modules/HyperStaking";
import LumiaDiamondModule from "../ignition/modules/LumiaDiamond";
import OneChainMailboxModule from "../ignition/modules/test/OneChainMailbox";
import SuperformMockModule from "../ignition/modules/test/SuperformMock";

import TestERC20Module from "../ignition/modules/test/TestERC20";
import TestRwaAssetModule from "../ignition/modules/test/TestRwaAsset";
import ReserveStrategyModule from "../ignition/modules/ReserveStrategy";
import ZeroYieldStrategyModule from "../ignition/modules/ZeroYieldStrategy";
import DirectStakeStrategyModule from "../ignition/modules/DirectStakeStrategy";

import { CurrencyStruct } from "../typechain-types/contracts/hyperstaking/interfaces/IHyperFactory";
import { IERC20 } from "../typechain-types";

// -------------------- Accounts --------------------

export async function getSigners() {
  const [
    owner, stakingManager, vaultManager, strategyManager, migrationManager, lumiaFactoryManager, lumiaRewardManager, bob, alice,
  ] = await ethers.getSigners();

  return { owner, stakingManager, vaultManager, strategyManager, migrationManager, lumiaFactoryManager, lumiaRewardManager, bob, alice };
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

  const { superformFactory, superformRouter, superVault, superPositions } = await ignition.deploy(SuperformMockModule, {
    parameters: {
      SuperformMockModule: {
        erc4626VaultAddress: await erc4626Vault.getAddress(),
      },
    },
  });

  const { diamond, deposit, hyperFactory, tier1, tier2, lockbox, migration, superformIntegration } = await ignition.deploy(HyperStakingModule, {
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

  const rwa1 = await ignition.deploy(TestRwaAssetModule);
  const rwaUSD = rwa1.rwaAsset;
  const rwaUSDOwner = rwa1.rwaAssetOwner;

  const rwa2 = await ignition.deploy(TestRwaAssetModule, {
    parameters: {
      TestRwaAssetModule: {
        name: "rwaETH",
        symbol: "rwaETH",
      },
    },
  });
  const rwaETH = rwa2.rwaAsset;
  const rwaETHOwner = rwa2.rwaAssetOwner;

  const { lumiaDiamond, hyperlaneHandler, realAssets, masterChef } = await ignition.deploy(LumiaDiamondModule, {
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

  // authorize lumia diamond to mint rwa assets
  await rwaUSDOwner.addMinter(lumiaDiamond);
  await rwaETHOwner.addMinter(lumiaDiamond);

  return {
    mailbox, hyperlaneHandler, diamond, deposit, hyperFactory, tier1, tier2, lockbox, superVault, migration, superformIntegration, lumiaDiamond, realAssets, masterChef, rwaUSD, rwaUSDOwner, rwaETH, rwaETHOwner,
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

  // full - because there are two differnet vesions of IERC20 used in the project
  const fullyQualifiedIERC20 = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";
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

export async function getDerivedTokens(tier2: Contract, routeFactory: Contract, strategy: string) {
  const vaultTokenAddress = (await tier2.tier2Info(strategy)).vaultToken;
  const vaultToken = await ethers.getContractAt("VaultToken", vaultTokenAddress);

  const lpTokenAddress = await routeFactory.getLpToken(strategy);
  const lpToken = await ethers.getContractAt("LumiaLPToken", lpTokenAddress);

  return { vaultToken, lpToken };
}

export async function getCurrentBlockTimestamp() {
  const blockNumber = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blockNumber);
  return block.timestamp;
}
