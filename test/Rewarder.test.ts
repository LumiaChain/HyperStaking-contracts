import { /* time, */ loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import hre from "hardhat";
import { parseEther } from "ethers";

import HyperStakingModule from "../ignition/modules/HyperStaking";
import ReserveStrategyModule from "../ignition/modules/ReserveStrategy";
import TestERC20Module from "../ignition/modules/TestERC20";

describe("Rewarder", function () {
  async function deployHyperStaking() {
    const [owner, alice] = await hre.ethers.getSigners();
    const { diamond, staking, vault, rewarder } = await hre.ignition.deploy(HyperStakingModule);

    const { testERC20 } = await hre.ignition.deploy(TestERC20Module, {
      parameters: {
        TestERC20Module: {
          symbol: "testWstETH",
          name: "Test Wrapped Liquid Staked ETH",
        },
      },
    });
    const testWstETH = testERC20;

    const nativeTokenAddress = await staking.nativeTokenAddress();
    await staking.createStakingPool(nativeTokenAddress);
    const ethPoolId = await staking.generatePoolId(nativeTokenAddress, 0);

    // -------------------- Apply Strategies --------------------

    // strategy asset price to eth 2:1
    const reserveAssetPrice = parseEther("2");

    const { reserveStrategy } = await hre.ignition.deploy(ReserveStrategyModule, {
      parameters: {
        ReserveStrategyModule: {
          diamond: await diamond.getAddress(),
          asset: await testWstETH.getAddress(),
          assetPrice: reserveAssetPrice,
        },
      },
    });

    const reserveStrategyAssetSupply = parseEther("55");
    await testWstETH.approve(reserveStrategy.target, reserveStrategyAssetSupply);
    await reserveStrategy.supplyRevenueAsset(reserveStrategyAssetSupply);

    await vault.addStrategy(ethPoolId, reserveStrategy, testWstETH);

    // -------------------- Add Rewarder --------------------

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, vault, rewarder, // diamond facets
      testWstETH, reserveStrategy, // test contracts
      ethPoolId, // ids
      reserveAssetPrice, reserveStrategyAssetSupply, // values
      owner, alice, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("Notify distribution", function () {
    it("Admin should be able to notify new distribution", async function () {
      const { rewarder } = await loadFixture(deployHyperStaking);
      console.log(rewarder.target);
    });
  });
});
