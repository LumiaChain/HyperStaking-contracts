import { ignition, ethers } from "hardhat";
import { Contract, ZeroAddress, parseEther } from "ethers";

import HyperStakingModule from "../ignition/modules/HyperStaking";
import LumiaDiamondModule from "../ignition/modules/LumiaDiamond";
import OneChainMailboxModule from "../ignition/modules/test/OneChainMailbox";
import SuperformMockModule from "../ignition/modules/test/SuperformMock";
import ThreeADaoMockModule from "../ignition/modules/test/3adaoMock";

import TestERC20Module from "../ignition/modules/test/TestERC20";
import ReserveStrategyModule from "../ignition/modules/ReserveStrategy";
import ZeroYieldStrategyModule from "../ignition/modules/ZeroYieldStrategy";

import { CurrencyStruct } from "../typechain-types/contracts/hyperstaking/interfaces/IHyperFactory";
import { IERC20 } from "../typechain-types";

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

  const { diamond, deposit, hyperFactory, tier1, tier2, lockbox, superformIntegration } = await ignition.deploy(HyperStakingModule, {
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

  const { rwaUSD, threeAVaultFactory, tokenToPriceFeed } = await ignition.deploy(ThreeADaoMockModule);

  const { lumiaDiamond, hyperlaneHandler, routeFactory } = await ignition.deploy(LumiaDiamondModule, {
    parameters: {
      LumiaDiamondModule: {
        lumiaMailbox: mailboxAddress,
        lumiaVaultFactory: await threeAVaultFactory.getAddress(),
      },
    },
  });

  // finish setup for hyperstaking
  const vaultManager = (await ethers.getSigners())[2];
  await lockbox.connect(vaultManager).setLumiaFactory(hyperlaneHandler);

  // finish setup for lumia diamond
  const lumiaFactoryManager = (await ethers.getSigners())[3];
  const lumiaAcl = await ethers.getContractAt("LumiaDiamondAcl", lumiaDiamond);
  await lumiaAcl.grantRole(
    await lumiaAcl.LUMIA_FACTORY_MANAGER_ROLE(),
    await lumiaFactoryManager.getAddress(),
  );

  const authorized = true;
  await hyperlaneHandler.connect(lumiaFactoryManager).updateAuthorizedOrigin(
    lockbox,
    authorized,
    testDestination,
  );

  return {
    mailbox, hyperlaneHandler, routeFactory, diamond, deposit, hyperFactory, tier1, tier2, lockbox, superVault, superformIntegration, rwaUSD, threeAVaultFactory, tokenToPriceFeed,
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

  const [owner, , , strategyManager] = await ethers.getSigners();

  const reserveStrategySupply = parseEther("30");

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

// -------------------- 3ADAO Lending --------------------

export async function addTestPriceFeed(
  tokenToPriceFeed: Contract,
  token: Contract,
  price: bigint,
) {
  const mcr = 100;
  const mlr = 100;
  const borrowRate = 0;

  const priceFeed = await ethers.deployContract("FixedPriceOracle", [token, price]);

  await tokenToPriceFeed.setTokenPriceFeed(
    token,
    priceFeed,
    mcr,
    mlr,
    borrowRate,
    0,
  );

  return priceFeed;
}

// -------------------- Other Helpers --------------------

export async function getDerivedTokens(tier2: Contract, routeFactory: Contract, strategy: string) {
  const vaultTokenAddress = (await tier2.vaultTier2Info(strategy)).vaultToken;
  const vaultToken = await ethers.getContractAt("VaultToken", vaultTokenAddress);

  const lpTokenAddress = await routeFactory.getLpToken(strategy);
  const lpToken = await ethers.getContractAt("LumiaLPToken", lpTokenAddress);

  return { vaultToken, lpToken };
}
