import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { parseEther } from "ethers";

import HyperStakingModule from "../ignition/modules/HyperStaking";
import PirexModule from "../ignition/modules/Pirex";
import TestERC20Module from "../ignition/modules/TestERC20";
import { PirexEth } from "../typechain-types";

describe("Strategy", function () {
  async function deployHyperStaking() {
    const [owner, alice] = await hre.ethers.getSigners();
    const { diamond } = await hre.ignition.deploy(HyperStakingModule);

    const stakingFacet = await hre.ethers.getContractAt("IStakingFacet", diamond);
    const strategyFacet = await hre.ethers.getContractAt("IStakingStrategy", diamond);

    const { testERC20 } = await hre.ignition.deploy(TestERC20Module, {
      parameters: {
        TestERC20Module: {
          symbol: "testWstETH",
          name: "Test Wrapped Liquid Staked ETH",
        },
      },
    });
    const testWstETH = testERC20;

    await stakingFacet.init();
    const nativeTokenAddress = await stakingFacet.nativeTokenAddress();
    const ethPoolId = await stakingFacet.generatePoolId(nativeTokenAddress, 0);

    // strategy with asset price to eth 2:1
    const assetPrice = parseEther("2");
    await strategyFacet.init(ethPoolId, testWstETH, assetPrice);
    const ethStrategy0Id = await strategyFacet.generateStrategyId(ethPoolId, 0);

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      stakingFacet, strategyFacet, // diamond facets
      testWstETH, // test tokens
      ethPoolId, ethStrategy0Id, // ids
      assetPrice, // values
      owner, alice, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  async function deployAndMockPirex() {
    const [owner, alice, rewardRecipient] = await hre.ethers.getSigners();

    const { pxEth, upxEth, pirexEth, autoPxEth } = await hre.ignition.deploy(PirexModule);

    // increase rewards buffer
    await (pirexEth.connect(rewardRecipient) as PirexEth).harvest(await ethers.provider.getBlockNumber(), { value: parseEther("100") });

    return { pxEth, upxEth, pirexEth, autoPxEth, owner, alice };
  }

  describe("ReserveStrategy", function () {
    it("Check state after allocation", async function () {
      const {
        stakingFacet, strategyFacet, ethPoolId, ethStrategy0Id, assetPrice, owner, alice,
      } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("4");

      // event
      await expect(stakingFacet.stakeDeposit(ethPoolId, ethStrategy0Id, stakeAmount, owner, { value: stakeAmount }))
        .to.emit(strategyFacet, "Allocate")
        .withArgs(ethStrategy0Id, ethPoolId, owner.address, stakeAmount);

      // event
      const stakeAmountForAlice = parseEther("11");
      await expect(stakingFacet.stakeDeposit(
        ethPoolId, ethStrategy0Id, stakeAmountForAlice, alice, { value: stakeAmountForAlice }),
      )
        .to.emit(strategyFacet, "Allocate")
        .withArgs(ethStrategy0Id, ethPoolId, alice.address, stakeAmountForAlice);

      // UserInfo
      expect(
        (await strategyFacet.userStrategyInfo(ethStrategy0Id, owner.address)).lockedStake,
      ).to.equal(stakeAmount);
      expect(
        (await strategyFacet.userStrategyInfo(ethStrategy0Id, owner.address)).revenueAssetAllocated,
      ).to.equal(stakeAmount * parseEther("1") / assetPrice);

      expect(
        (await strategyFacet.userStrategyInfo(ethStrategy0Id, alice.address)).lockedStake,
      ).to.equal(stakeAmountForAlice);
      expect(
        (await strategyFacet.userStrategyInfo(ethStrategy0Id, alice.address)).revenueAssetAllocated,
      ).to.equal(stakeAmountForAlice * parseEther("1") / assetPrice);

      // StrategyInfo TODO

      // AssetInfo TODO
    });

    it("Check state after exit", async function () {
      const { stakingFacet, strategyFacet, ethPoolId, ethStrategy0Id, assetPrice, owner } = await loadFixture(deployHyperStaking);
      const stakeAmount = parseEther("2.4");
      const withdrawAmount = parseEther("0.6");

      await stakingFacet.stakeDeposit(ethPoolId, ethStrategy0Id, stakeAmount, owner, { value: stakeAmount });

      // event
      await expect(stakingFacet.stakeWithdraw(ethPoolId, ethStrategy0Id, withdrawAmount, owner))
        .to.emit(strategyFacet, "Exit")
        .withArgs(ethStrategy0Id, ethPoolId, owner.address, withdrawAmount, 0); // 0 - revenue

      // UserInfo
      expect(
        (await strategyFacet.userStrategyInfo(ethStrategy0Id, owner.address)).lockedStake,
      ).to.equal(stakeAmount - withdrawAmount);
      expect(
        (await strategyFacet.userStrategyInfo(ethStrategy0Id, owner.address)).revenueAssetAllocated,
      ).to.equal((stakeAmount - withdrawAmount) * parseEther("1") / assetPrice);

      // StrategyInfo TODO

      // AssetInfo TODO
    });

    it("StrategyID generation check", async function () {
      const { strategyFacet } = await loadFixture(deployHyperStaking);

      const randomPoolId = "0xb5b24b02e0833f9405dbb2849b857fcaed85ef525039c7db2618d9a23eb90a50";

      const generatedStrategyId = await strategyFacet.generateStrategyId(randomPoolId, 3);
      const expectedPoolId = hre.ethers.keccak256(
        hre.ethers.solidityPacked(["uint256", "uint256"], [randomPoolId, 3]),
      );
      expect(generatedStrategyId).to.equal(expectedPoolId);

      const generatedStrategyId2 = await strategyFacet.generateStrategyId(randomPoolId, 15);
      const expectedStrategyId2 = hre.ethers.keccak256(
      // <-                       256 bits poolId                       -><-                       256 bits idx                          ->
        "0xb5b24b02e0833f9405dbb2849b857fcaed85ef525039c7db2618d9a23eb90a50000000000000000000000000000000000000000000000000000000000000000f",
      );
      expect(generatedStrategyId2).to.equal(expectedStrategyId2);

      // TODO
      // const generatedStrategyId3 = await strategyFacet.generateStrategyId(randomPoolId, 0);
      // const expectedStrategyId3 = "0xaa23c5840318d20f0f24889b5f776f74cb488aff8d16ad9856c44f40c5d13d23";
      //
      // expect(generatedStrategyId3).to.equal(expectedStrategyId3);
    });

    describe("Errors", function () {
      // TODO
      // it("StrategyDoesNotExist", async function () {
      //  const { stakingFacet, ethPoolId, owner } = await loadFixture(deployHyperStaking);
      //
      //  const badStrategyId = "0xabca816169f82123e129cf759e8d851bd8a678458c95df05d183240301c330f9";
      //
      //  await expect(stakingFacet.stakeDeposit(ethPoolId, badStrategyId, 1, owner, { value: 1 }))
      //    .to.be.revertedWithCustomError(stakingFacet, "StrategyDoesNotExist");
      // });
    });
  });

  describe.only("Pirex integration", function () {
    it("It should be possible to deposit ETH and get pxETH", async function () {
      const { pxEth, pirexEth, owner } = await loadFixture(deployAndMockPirex);

      await pirexEth.deposit(owner.address, false, { value: parseEther("1") });

      expect(await pxEth.balanceOf(owner.address)).to.be.greaterThan(0);
    });

    it("It should be possible to deposit ETH and auto-compund it with apxEth", async function () {
      const { pxEth, pirexEth, autoPxEth, owner } = await loadFixture(deployAndMockPirex);

      await pirexEth.deposit(owner.address, true, { value: parseEther("5") });

      expect(await pxEth.balanceOf(owner.address)).to.equal(0);
      expect(await autoPxEth.balanceOf(owner.address)).to.be.greaterThan(0);
    });

    it("It should be possible to instant Redeem apxEth back to ETH", async function () {
      const { pxEth, pirexEth, autoPxEth, owner, alice } = await loadFixture(deployAndMockPirex);

      const initialDeposit = parseEther("1");
      await pirexEth.deposit(owner.address, true, { value: initialDeposit });

      const totalAssets = await autoPxEth.totalAssets();
      await autoPxEth.withdraw(totalAssets / 2n, owner.address, owner.address);

      await expect(pirexEth.instantRedeemWithPxEth(initialDeposit / 2n, alice.address))
        .to.changeEtherBalances(
          [pirexEth, alice],
          [-initialDeposit / 2n, initialDeposit / 2n],
        );

      expect(await pxEth.balanceOf(owner.address)).to.equal(0);
    });
  });
});
