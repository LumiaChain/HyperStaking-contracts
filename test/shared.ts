import { ignition } from "hardhat";
import { Contract } from "ethers";
import TestERC20Module from "../ignition/modules/TestERC20";
import ReserveStrategyModule from "../ignition/modules/ReserveStrategy";

export async function deloyTestERC20(name: string, symbol: string) {
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
  const nativeTokenAddress = await staking.nativeTokenAddress();
  await staking.createStakingPool(nativeTokenAddress);
  const ethPoolId = await staking.generatePoolId(nativeTokenAddress, 0);

  return { nativeTokenAddress, ethPoolId };
}

export async function createStakingPool(staking: Contract, token: Contract) {
  await staking.createStakingPool(token);
  const poolCount = await staking.stakeTokenPoolCount(token);
  const poolId = await staking.generatePoolId(token, poolCount - 1n);

  return poolId;
}

export async function createReserveStrategy(diamond: Contract, asset: Contract, assetPrice: bigint) {
  const { reserveStrategy } = await ignition.deploy(ReserveStrategyModule, {
    parameters: {
      ReserveStrategyModule: {
        diamond: await diamond.getAddress(),
        asset: await asset.getAddress(),
        assetPrice,
      },
    },
  });

  return reserveStrategy;
}
