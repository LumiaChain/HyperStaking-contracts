import { ignition, ethers } from "hardhat";
import { Contract, ZeroAddress } from "ethers";
import TestERC20Module from "../ignition/modules/TestERC20";
import ReserveStrategyModule from "../ignition/modules/ReserveStrategy";
import { CurrencyStruct } from "../typechain-types/contracts/hyperstaking/facets/StakingFacet";

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

  return reserveStrategy;
}
