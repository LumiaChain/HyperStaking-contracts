import { ignition, ethers } from "hardhat";
import { Contract, ZeroAddress, parseEther } from "ethers";

import HyperStakingModule from "../ignition/modules/HyperStaking";
import OneChainMailboxModule from "../ignition/modules/test/OneChainMailbox";

import TestERC20Module from "../ignition/modules/test/TestERC20";
import LumiaXERC20Module from "../ignition/modules/LumiaXERC20";
import ReserveStrategyModule from "../ignition/modules/ReserveStrategy";

import { CurrencyStruct } from "../typechain-types/contracts/hyperstaking/facets/StakingFacet";
import { IERC20 } from "../typechain-types";

export async function deployTestHyperStaking(mailboxFee: bigint) {
  const { mailbox } = await ignition.deploy(OneChainMailboxModule, {
    parameters: {
      OneChainMailboxModule: {
        fee: mailboxFee,
      },
    },
  });

  const mailboxAddress = await mailbox.getAddress();

  const recipient = await ethers.deployContract("Recipient", [mailboxAddress]);

  const testDestination = 31337;

  const { diamond, staking, factory, tier1, tier2, lockbox } = await ignition.deploy(HyperStakingModule, {
    parameters: {
      HyperStakingModule: {
        lockboxMailbox: mailboxAddress,
        lockboxDestination: testDestination,
        lockboxRecipient: await recipient.getAddress(),
      },
    },
  });

  await recipient.setOriginLockbox(await diamond.getAddress());

  return { mailbox, recipient, diamond, staking, factory, tier1, tier2, lockbox };
}

export async function deloyTestERC20(name: string, symbol: string): Promise<Contract> {
  const { testERC20 } = await ignition.deploy(TestERC20Module, {
    parameters: {
      TestERC20Module: {
        name,
        symbol,
      },
    },
  });
  return testERC20;
}

export async function deloyTestXERC20(mailbox: string, name: string, symbol: string): Promise<Contract> {
  const { xERC20 } = await ignition.deploy(LumiaXERC20Module, {
    parameters: {
      LumiaXERC20Module: {
        mailbox,
        name,
        symbol,
      },
    },
  });
  return xERC20;
}

export async function createNativeStakingPool(staking: Contract) {
  const stakingManager = (await ethers.getSigners())[1];

  const nativeTokenAddress = ZeroAddress;
  const currency = { token: nativeTokenAddress } as CurrencyStruct;

  await staking.connect(stakingManager).createStakingPool(currency);
  const ethPoolId = await staking.generatePoolId(currency, 0);

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
  const asset = (await ethers.getContractAt("IERC20", assetAddress)) as IERC20;

  await asset.approve(reserveStrategy.target, reserveStrategySupply);
  await reserveStrategy.supplyRevenueAsset(reserveStrategySupply);

  const [owner] = await ethers.getSigners();
  await owner.sendTransaction({
    to: reserveStrategy,
    value: reserveStrategySupply,
  });

  return reserveStrategy;
}
