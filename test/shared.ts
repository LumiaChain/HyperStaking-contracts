import { ignition, ethers } from "hardhat";
import { Contract, ZeroAddress, parseEther } from "ethers";

import HyperStakingModule from "../ignition/modules/HyperStaking";
import LumiaDiamondModule from "../ignition/modules/LumiaDiamond";
import OneChainMailboxModule from "../ignition/modules/test/OneChainMailbox";
import SuperformMockModule from "../ignition/modules/test/SuperformMock";

import TestERC20Module from "../ignition/modules/test/TestERC20";
import ReserveStrategyModule from "../ignition/modules/ReserveStrategy";

import { CurrencyStruct } from "../typechain-types/contracts/hyperstaking/facets/StakingFacet";
import { IERC20 } from "../typechain-types";

export async function deployTestHyperStaking(mailboxFee: bigint, erc4626Vault: Contract) {
  const testDestination = 31337; // the same for both sides of the test "oneChain" bridge

  const { mailbox } = await ignition.deploy(OneChainMailboxModule, {
    parameters: {
      OneChainMailboxModule: {
        fee: mailboxFee,
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

  const { diamond, staking, vaultFactory, tier1, tier2, lockbox, superformIntegration } = await ignition.deploy(HyperStakingModule, {
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

  const { lumiaDiamond, interchainFactory } = await ignition.deploy(LumiaDiamondModule, {
    parameters: {
      LumiaDiamondModule: {
        lumiaMailbox: mailboxAddress,
        lumiaDestination: testDestination,
        originLockbox: await lockbox.getAddress(),
      },
    },
  });

  // finish setup for hyperstaking
  const strategyVaultManager = (await ethers.getSigners())[2];
  await lockbox.connect(strategyVaultManager).setLumiaFactory(interchainFactory);

  // finish setup for lumia diamond
  const lumiaFactoryManager = (await ethers.getSigners())[3];
  const lumiaAcl = await ethers.getContractAt("LumiaDiamondAcl", lumiaDiamond);
  await lumiaAcl.grantRole(
    await lumiaAcl.LUMIA_FACTORY_MANAGER_ROLE(),
    await lumiaFactoryManager.getAddress(),
  );

  return {
    mailbox, interchainFactory, diamond, staking, vaultFactory, tier1, tier2, lockbox, superVault, superformIntegration,
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

export async function createNativeStakingPool(staking: Contract) {
  const stakingManager = (await ethers.getSigners())[1];

  const nativeTokenAddress = ZeroAddress;
  const currency = { token: nativeTokenAddress } as CurrencyStruct;

  await staking.connect(stakingManager).createStakingPool(currency);

  const poolCount = await staking.stakeTokenPoolCount(currency);
  const ethPoolId = await staking.generatePoolId(currency, poolCount - 1n);

  return { nativeTokenAddress, ethPoolId };
}

export async function createStakingPool(staking: Contract, token: Contract) {
  const stakingManager = (await ethers.getSigners())[1];
  const currency = { token } as CurrencyStruct;

  await staking.connect(stakingManager).createStakingPool(currency);
  const poolCount = await staking.stakeTokenPoolCount(currency);
  const poolId = await staking.generatePoolId(currency, poolCount - 1n);

  return poolId;
}

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

  const reserveStrategySupply = parseEther("30");

  // because there are two differnet vesions of IERC20 used in the project
  const fullyQualifiedIERC20 = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";
  const asset = (await ethers.getContractAt(fullyQualifiedIERC20, assetAddress)) as unknown as IERC20;

  await asset.approve(reserveStrategy.target, reserveStrategySupply);
  await reserveStrategy.supplyRevenueAsset(reserveStrategySupply);

  const [owner] = await ethers.getSigners();
  await owner.sendTransaction({
    to: reserveStrategy,
    value: reserveStrategySupply,
  });

  return reserveStrategy;
}

export async function getDerivedTokens(tier2: Contract, interchainFactory: Contract, strategy: string) {
  const vaultTokenAddress = (await tier2.vaultTier2Info(strategy)).vaultToken;
  const vaultToken = await ethers.getContractAt("VaultToken", vaultTokenAddress);

  const lpTokenAddress = await interchainFactory.getLpToken(vaultTokenAddress);
  const lpToken = await ethers.getContractAt("LumiaLPToken", lpTokenAddress);

  return { vaultToken, lpToken };
}
