import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";
import { Contract, parseEther, parseUnits, ZeroAddress } from "ethers";

import HyperStakingModule from "../ignition/modules/HyperStaking";

import * as shared from "./shared";

describe("Rewarder", function () {
  async function deployHyperStaking() {
    const [owner, alice, bob] = await hre.ethers.getSigners();
    const { diamond, staking, vault, rewarder } = await hre.ignition.deploy(HyperStakingModule);

    const REWARD_PRECISION = await rewarder.REWARD_PRECISION();
    const REWARDS_PER_STRATEGY_LIMIT = await rewarder.REWARDS_PER_STRATEGY_LIMIT();

    const testWstETH = await shared.deloyTestERC20("Test Wrapped Liquid Staked ETH", "tWstETH");
    const rewardToken = await shared.deloyTestERC20("Test Reward Token", "rERC");

    // ------------------ Create Staking Pools ------------------

    const { nativeTokenAddress, ethPoolId } = await shared.createNativeStakingPool(staking);

    // -------------------- Apply Strategies --------------------

    // strategy asset price to eth 2:1
    const reserveAssetPrice = parseEther("2");
    const reserveStrategy = await shared.createReserveStrategy(diamond, testWstETH, reserveAssetPrice);

    const reserveStrategyAssetSupply = parseEther("55");
    await testWstETH.approve(reserveStrategy.target, reserveStrategyAssetSupply);
    await reserveStrategy.supplyRevenueAsset(reserveStrategyAssetSupply);

    await vault.addStrategy(ethPoolId, reserveStrategy, testWstETH);

    // -------------------- Add Rewarder --------------------

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, vault, rewarder, // diamond facets
      testWstETH, rewardToken, reserveStrategy, // test contracts
      ethPoolId, // ids
      reserveAssetPrice, reserveStrategyAssetSupply, // values
      nativeTokenAddress, owner, alice, bob, // addresses
      REWARD_PRECISION, REWARDS_PER_STRATEGY_LIMIT, // constants
    };
    /* eslint-enable object-property-newline */
  }

  async function deployTestTokens() {
    const testTokens: Contract[] = [];

    // deploy 6 test tokens
    for (let i = 1; i <= 6; i++) {
      const name = `TestToken${i}`;
      const symbol = `tt${i}`;
      testTokens.push(await shared.deloyTestERC20(name, symbol));
    }

    return { testTokens };
  }

  describe("Reward distribution", function () {
    it("Empty rewarder values", async function () {
      const { reserveStrategy, rewarder, alice } = await loadFixture(deployHyperStaking);

      const badRewardIdx = 0;
      expect(await rewarder.isRewardActive(reserveStrategy, badRewardIdx)).to.be.eq(false);
      expect(await rewarder.strategyIndex(reserveStrategy)).to.be.eq(0);
      expect(await rewarder.activeRewardList(reserveStrategy)).to.be.deep.eq([]);

      // these function should not revert even if there are no rewarders
      await expect(rewarder.updateActivePools(reserveStrategy, ZeroAddress)).not.to.be.reverted;
      await expect(rewarder.updateActivePools(reserveStrategy, alice.address)).not.to.be.reverted;
      await expect(rewarder.claimAll(reserveStrategy, alice.address)).not.to.be.reverted;

      // but specific reward throw "not found"
      await expect(rewarder.claimReward(reserveStrategy, badRewardIdx, alice.address))
        .to.be.revertedWithCustomError(rewarder, "RewardNotFound");

      await expect(rewarder.updatePool(reserveStrategy, badRewardIdx))
        .to.be.revertedWithCustomError(rewarder, "RewardNotFound");

      await expect(rewarder.updateUser(reserveStrategy, badRewardIdx, alice.address))
        .to.be.revertedWithCustomError(rewarder, "RewardNotFound");

      await expect(rewarder.pendingReward(reserveStrategy, badRewardIdx, alice.address))
        .to.be.revertedWithCustomError(rewarder, "RewardNotFound");

      await expect(rewarder.userRewardInfo(reserveStrategy, badRewardIdx, alice.address))
        .to.be.revertedWithCustomError(rewarder, "RewardNotFound");

      await expect(rewarder.strategyRewardInfo(reserveStrategy, badRewardIdx))
        .to.be.revertedWithCustomError(rewarder, "RewardNotFound");

      await expect(rewarder.balance(reserveStrategy, badRewardIdx))
        .to.be.revertedWithCustomError(rewarder, "RewardNotFound");

      await expect(rewarder.rewardPool(reserveStrategy, badRewardIdx))
        .to.be.revertedWithCustomError(rewarder, "RewardNotFound");

      await expect(rewarder.finalize(reserveStrategy, badRewardIdx))
        .to.be.revertedWithCustomError(rewarder, "RewardNotFound");
    });

    // TODO
    // it("Only RewardsManager should be able to notify new distribution", async function ()

    it("Create new reward distribution", async function () {
      const { rewardToken, reserveStrategy, rewarder, owner } = await loadFixture(deployHyperStaking);

      const rewardAmount = parseEther("100");
      await rewardToken.approve(rewarder, rewardAmount);

      const startTimestamp = Math.floor(Date.now() / 1000) + 100;
      await time.setNextBlockTimestamp(startTimestamp);
      const distributionEnd = Math.floor(startTimestamp + 1000);

      const rewardIdx = 0;
      await expect(rewarder.newRewardDistribution(
        reserveStrategy,
        rewardToken,
        rewardAmount,
        0, // - now (startTimestamp)
        distributionEnd,
      )).to.emit(rewarder, "RewardNotify")
        .withArgs(owner.address, reserveStrategy, rewardIdx, rewardAmount, 0, startTimestamp, distributionEnd, true);

      const rewardPool = await rewarder.rewardPool(reserveStrategy, rewardIdx);
      expect(rewardPool.tokensPerSecond).to.eq(rewardAmount * parseUnits("1", 36) / BigInt(distributionEnd - startTimestamp));
    });

    it("Reward creation should revert in some cases", async function () {
      const { rewardToken, reserveStrategy, rewarder } = await loadFixture(deployHyperStaking);

      await expect(rewarder.newRewardDistribution(
        reserveStrategy,
        ZeroAddress,
        0,
        0,
        0,
      )).to.be.revertedWithCustomError(rewarder, "TokenZeroAddress");

      let startTimestamp = Math.floor(Date.now() / 1000) - 100;

      await expect(rewarder.newRewardDistribution(
        reserveStrategy,
        rewardToken,
        0,
        startTimestamp,
        0,
      )).to.be.revertedWithCustomError(rewarder, "StartTimestampPassed");

      startTimestamp = Math.floor(Date.now() / 1000) + 100;

      await expect(rewarder.newRewardDistribution(
        reserveStrategy,
        rewardToken,
        0,
        startTimestamp,
        startTimestamp,
      )).to.be.revertedWithCustomError(rewarder, "InvalidDistributionRange");

      const rewardAmount = parseUnits("1", 30) + 1n;

      await expect(rewarder.newRewardDistribution(
        reserveStrategy,
        rewardToken,
        rewardAmount, // too big value
        startTimestamp,
        startTimestamp + 1, // 1 second distribution
      )).to.be.revertedWithCustomError(rewarder, "RateTooHigh");
    });

    it("Reward shouldn't be distribute after its end", async function () {
      const {
        staking, rewarder, rewardToken, reserveStrategy, ethPoolId, alice, REWARD_PRECISION,
      } = await loadFixture(deployHyperStaking);

      const rewardIdx = 0;
      const rewardAmount = parseEther("100");
      await rewardToken.approve(rewarder, rewardAmount);

      const startTimestamp = Math.floor(Date.now() / 1000) + 100;
      const distributionDuration = 1000; // seconds
      const distributionEnd = Math.floor(startTimestamp + distributionDuration);

      await time.setNextBlockTimestamp(startTimestamp - 1);

      // notify when there are no stakers yet
      await rewarder.newRewardDistribution(
        reserveStrategy,
        rewardToken,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      );

      const stakeAmount = parseEther("1");
      await staking.connect(alice).stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      await time.increase(distributionDuration);

      // the whole reward
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, alice.address)).to.eq(rewardAmount);

      // update pool to check userRewardInfo
      await rewarder.updatePool(reserveStrategy, rewardIdx);
      await rewarder.updateUser(reserveStrategy, rewardIdx, alice.address);

      const expectedRewardPerTokenPaid = rewardAmount * REWARD_PRECISION / stakeAmount;

      // info before claim
      let userRewardInfo = await rewarder.userRewardInfo(reserveStrategy, rewardIdx, alice.address);
      expect(userRewardInfo.rewardPerTokenPaid).to.eq(expectedRewardPerTokenPaid);

      await expect(rewarder.connect(alice).claimReward(reserveStrategy, rewardIdx, alice.address))
        .to.changeTokenBalances(rewardToken,
          [alice, rewarder],
          [rewardAmount, -rewardAmount],
        );

      // info after claim
      userRewardInfo = await rewarder.userRewardInfo(reserveStrategy, rewardIdx, alice.address);
      expect(userRewardInfo.rewardPerTokenPaid).to.eq(expectedRewardPerTokenPaid);
      expect(userRewardInfo.rewardUnclaimed).to.eq(0);

      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, alice.address)).to.eq(0);

      // withdraw should work as expected
      await expect(staking.connect(alice).stakeWithdraw(ethPoolId, reserveStrategy, stakeAmount, alice))
        .to.changeEtherBalances(
          [alice, reserveStrategy],
          [stakeAmount, -stakeAmount],
        );

      // info after withdraw
      userRewardInfo = await rewarder.userRewardInfo(reserveStrategy, rewardIdx, alice.address);
      expect(userRewardInfo.rewardPerTokenPaid).to.eq(expectedRewardPerTokenPaid);
      expect(userRewardInfo.rewardUnclaimed).to.eq(0);
    });

    it("Reward should be applied to current stakers too", async function () {
      const {
        staking, rewarder, rewardToken, reserveStrategy, ethPoolId, alice, REWARD_PRECISION,
      } = await loadFixture(deployHyperStaking);

      const rewardIdx = 0;
      const rewardAmount = parseEther("50");
      await rewardToken.approve(rewarder, rewardAmount);

      const stakeAmount = parseEther("1");
      await staking.connect(alice).stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      const startTimestamp = Math.floor(Date.now() / 1000) + 100;
      const distributionDuration = 10000; // seconds
      const distributionEnd = Math.floor(startTimestamp + distributionDuration);
      await time.setNextBlockTimestamp(startTimestamp);

      // notify when there are already stakers
      await rewarder.newRewardDistribution(
        reserveStrategy,
        rewardToken,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      );

      await time.increase(distributionDuration);

      const rewardPool = await rewarder.rewardPool(reserveStrategy, rewardIdx);
      expect(rewardPool.tokensPerSecond).to.eq(rewardAmount * REWARD_PRECISION / BigInt(distributionDuration));
      expect(rewardPool.rewardPerToken).to.eq(0);
      expect(rewardPool.lastRewardTimestamp).to.eq(startTimestamp);

      // reward should be counted even if the user did not stake after notify
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, alice.address)).to.eq(rewardAmount);

      // info before claim
      let userRewardInfo = await rewarder.userRewardInfo(reserveStrategy, rewardIdx, alice.address);
      expect(userRewardInfo.rewardPerTokenPaid).to.eq(0);
      expect(userRewardInfo.rewardUnclaimed).to.eq(0);

      await expect(rewarder.connect(alice).claimAll(reserveStrategy, alice.address))
        .to.changeTokenBalances(rewardToken,
          [alice, rewarder],
          [rewardAmount, -rewardAmount],
        );

      // withdraw should work as expected
      await expect(staking.connect(alice).stakeWithdraw(ethPoolId, reserveStrategy, stakeAmount, alice))
        .to.changeEtherBalances(
          [alice, reserveStrategy],
          [stakeAmount, -stakeAmount],
        );

      // claim after withdraw should work too
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, alice.address)).to.eq(0);

      // info after withdraw
      userRewardInfo = await rewarder.userRewardInfo(reserveStrategy, rewardIdx, alice.address);
      expect(userRewardInfo.rewardPerTokenPaid).to.eq(rewardAmount * REWARD_PRECISION / stakeAmount);
      expect(userRewardInfo.rewardUnclaimed).to.eq(0);
    });

    it("Check calculations for more than one staker", async function () {
      const { staking, rewarder, rewardToken, reserveStrategy, ethPoolId, alice, bob } = await loadFixture(deployHyperStaking);

      const rewardIdx = 0;
      const rewardAmount = parseEther("6000");
      await rewardToken.approve(rewarder, rewardAmount);

      // alice stakes first
      const stakeAmount = parseEther("1");
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      const startTimestamp = Math.floor(Date.now() / 1000) + 100;
      const distributionDuration = 20000; // seconds
      const distributionEnd = Math.floor(startTimestamp + distributionDuration);
      await time.setNextBlockTimestamp(startTimestamp);

      // notify when there are already stakers
      await rewarder.newRewardDistribution(
        reserveStrategy,
        rewardToken,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      );

      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, alice.address)).to.eq(0);
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, bob.address)).to.eq(0);

      // 1/2 of the distributionDuration
      await time.increase(distributionDuration / 2 - 1);

      // bob enters with the same stake as alice
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, bob, { value: stakeAmount });

      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, alice.address)).to.eq(rewardAmount / 2n);
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, bob.address)).to.eq(0);

      // finish distribution
      await time.increase(distributionDuration / 2 + 1);

      // alice should get around 3/4 and bob 1/4 of the reward
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, alice.address)).to.eq(rewardAmount * 3n / 4n);
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, bob.address)).to.eq(rewardAmount / 4n);

      await expect(rewarder.connect(alice).claimReward(reserveStrategy, rewardIdx, alice.address))
        .to.changeTokenBalances(rewardToken,
          [alice, rewarder],
          [rewardAmount * 3n / 4n, -rewardAmount * 3n / 4n],
        );

      await expect(rewarder.connect(bob).claimAll(reserveStrategy, bob.address))
        .to.changeTokenBalances(rewardToken,
          [bob, rewarder],
          [rewardAmount / 4n, -rewardAmount / 4n],
        );
    });

    it("extending reward distribution should be possible, leftover", async function () {
      const { staking, rewarder, rewardToken, reserveStrategy, ethPoolId, alice, bob } = await loadFixture(deployHyperStaking);

      const rewardIdx = 0;
      const rewardAmount1 = parseEther("2000");
      const rewardAmount2 = parseEther("4000");
      await rewardToken.approve(rewarder, rewardAmount1);

      // alice stakes
      const stakeAmount = parseEther("1");
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      const startTimestamp = Math.floor(Date.now() / 1000) + 100;
      const distributionDuration = 2000; // seconds
      const distributionEnd = Math.floor(startTimestamp + distributionDuration);
      await time.setNextBlockTimestamp(startTimestamp);

      // notify rewardAmount1
      await rewarder.newRewardDistribution(
        reserveStrategy,
        rewardToken,
        rewardAmount1,
        startTimestamp,
        distributionEnd,
      );

      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, alice.address)).to.eq(0);
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, bob.address)).to.eq(0);

      // 1/2 of the distributionDuration
      await time.increase(distributionDuration / 2 - 1);

      // bob stakes
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, bob, { value: stakeAmount });

      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, alice.address)).to.eq(rewardAmount1 / 2n);
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, bob.address)).to.eq(0);

      // notify second reward distribution when first didnt finish yet - rewardAmount2
      await rewardToken.approve(rewarder, rewardAmount2);
      await rewarder.notifyRewardDistribution(
        reserveStrategy,
        rewardIdx,
        rewardAmount2,
        0, // - now (startTimestamp / 2 - 1)
        distributionEnd + distributionDuration / 2,
      );

      // finish second distribution
      await time.increase(distributionDuration);

      // bob should receive around half of the second reward distribution, which combines
      // the leftover from the first reward and the entire second reward
      let expectedBobReward = (rewardAmount1 / 2n + rewardAmount2) / 2n;

      // alice should receive the same amount as bob, plus half of the first reward
      let expectedAliceReward = rewardAmount1 / 2n + expectedBobReward;

      const precisionError = 1n; // 1 wei
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, alice.address))
        .to.eq(expectedAliceReward - precisionError);
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, bob.address))
        .to.eq(expectedBobReward - precisionError);

      // ------------------------------

      // lets notifu a new distribution after some time has passed
      await time.increase(distributionDuration * 5);

      const rewardAmount3 = parseEther("10000");
      await rewardToken.approve(rewarder, rewardAmount3);

      const start3 = await time.latest() + 1;
      const duration3 = 100; // seconds
      const end3 = start3 + duration3;
      await time.setNextBlockTimestamp(start3);

      // notify rewardAmount3
      await rewarder.notifyRewardDistribution(
        reserveStrategy,
        rewardIdx,
        rewardAmount3,
        start3,
        end3,
      );

      // finish third distribution
      await time.increase(duration3);

      // check pending rewards
      expectedAliceReward += rewardAmount3 / 2n;
      expectedBobReward += rewardAmount3 / 2n;

      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, alice.address))
        .to.eq(expectedAliceReward - precisionError);
      expect(await rewarder.pendingReward(reserveStrategy, rewardIdx, bob.address))
        .to.eq(expectedBobReward - precisionError);

      // claims

      await expect(rewarder.connect(alice).claimAll(reserveStrategy, alice.address))
        .to.changeTokenBalances(rewardToken,
          [alice, rewarder],
          [expectedAliceReward - precisionError, -expectedAliceReward + precisionError],
        );

      await expect(rewarder.connect(bob).claimReward(reserveStrategy, rewardIdx, bob.address))
        .to.changeTokenBalances(rewardToken,
          [bob, rewarder],
          [expectedBobReward - precisionError, -expectedBobReward + precisionError],
        );
    });

    // TODO add ACL
    it("It should be possible to finalize rewarder and claim remaining tokens", async function () {
      const { staking, rewarder, rewardToken, reserveStrategy, ethPoolId, owner, alice } = await loadFixture(deployHyperStaking);

      const rewardIdx = 0;
      const rewardAmount = parseEther("6000");
      await rewardToken.approve(rewarder, rewardAmount);

      const startTimestamp = await time.latest() + 1;
      const distributionDuration = 1500; // seconds
      const distributionEnd = Math.floor(startTimestamp + distributionDuration);
      await time.setNextBlockTimestamp(startTimestamp);

      // notify when there are already stakers
      await rewarder.newRewardDistribution(
        reserveStrategy,
        rewardToken,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      );

      expect(await rewarder.strategyIndex(reserveStrategy)).to.be.eq(1);
      expect(await rewarder.isRewardActive(reserveStrategy, rewardIdx)).to.be.eq(true);

      const stakeAmount = parseEther("1");
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      await expect(rewarder.withdrawRemaining(reserveStrategy, rewardIdx, owner))
        .to.revertedWithCustomError(rewarder, "NotFinalized");

      // finalize in 1/3 of the distributionDuration
      const finalizeTimestamp = startTimestamp + distributionDuration / 3;
      await time.setNextBlockTimestamp(finalizeTimestamp);

      // finalize rewarder
      await expect(rewarder.finalize(reserveStrategy, rewardIdx))
        .to.emit(rewarder, "Finalize")
        .withArgs(owner.address, reserveStrategy, rewardIdx, finalizeTimestamp);

      const rewardInfo = await rewarder.strategyRewardInfo(reserveStrategy, rewardIdx);
      expect(rewardInfo.rewardToken).to.eq(rewardToken);
      expect(rewardInfo.finalized).to.eq(finalizeTimestamp);

      expect(await rewarder.isRewardActive(reserveStrategy, rewardIdx)).to.be.eq(false);
      const expectedRewarderBalance = rewardAmount * 2n / 3n;
      expect(await rewarder.balance(reserveStrategy, rewardIdx)).to.eq(expectedRewarderBalance);

      // should not change the withdraw balance
      await time.increase(1000);

      await expect(rewarder.withdrawRemaining(reserveStrategy, rewardIdx, owner))
        .to.changeTokenBalances(rewardToken,
          [owner, rewarder],
          [expectedRewarderBalance, -expectedRewarderBalance],
        );

      // should not be possible to notify new distribution on finalized rewarder
      await expect(rewarder.notifyRewardDistribution(
        reserveStrategy,
        rewardIdx,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      )).to.be.revertedWithCustomError(rewarder, "Finalized");
    });
  });

  describe("Concurrent rewards", function () {
    it("multiple rewards limitations", async function () {
      const { rewarder, reserveStrategy, REWARDS_PER_STRATEGY_LIMIT } = await loadFixture(deployHyperStaking);

      const { testTokens } = await deployTestTokens();

      const rewardAmount = parseEther("100");

      const startTimestamp = await time.latest() + 100;
      const distributionEnd = startTimestamp + 1000;

      for (let i = 0; i < REWARDS_PER_STRATEGY_LIMIT; i++) {
        await testTokens[i].approve(rewarder, rewardAmount);
        await rewarder.newRewardDistribution(
          reserveStrategy,
          testTokens[i],
          rewardAmount,
          startTimestamp,
          distributionEnd,
        );
      }

      await expect(rewarder.newRewardDistribution(
        reserveStrategy,
        testTokens[REWARDS_PER_STRATEGY_LIMIT].target,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      )).to.be.revertedWithCustomError(rewarder, "ActiveRewardsLimitReached");
    });

    it("multiple rewards", async function () {
      const { staking, rewarder, reserveStrategy, ethPoolId, alice, REWARDS_PER_STRATEGY_LIMIT } = await loadFixture(deployHyperStaking);
      const { testTokens } = await deployTestTokens();

      const stakeAmount = parseEther("1");
      await staking.connect(alice).stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      const baseRewardAmount = parseEther("100");

      const startTimestamp = await time.latest() + 100;
      const distributionDuration = 10000;
      const distributionEnd = startTimestamp + distributionDuration;

      // create many rewards distribution for the same strategy
      for (let i = 0; i < REWARDS_PER_STRATEGY_LIMIT; i++) {
        const rewardAmount = baseRewardAmount * BigInt(i + 1);
        await testTokens[i].approve(rewarder, rewardAmount);
        await rewarder.newRewardDistribution(
          reserveStrategy,
          testTokens[i],
          rewardAmount,
          startTimestamp,
          distributionEnd,
        );
      }

      // finish all distributions
      await time.increase(distributionDuration + 100);

      for (let i = 0; i < REWARDS_PER_STRATEGY_LIMIT; i++) {
        const rewardAmount = baseRewardAmount * BigInt(i + 1);
        expect(await rewarder.pendingReward(reserveStrategy, i, alice.address)).to.eq(rewardAmount);
      }

      // claim all rewards
      const tx = rewarder.connect(alice).claimAll(reserveStrategy, alice.address);

      for (let i = 0; i < REWARDS_PER_STRATEGY_LIMIT; i++) {
        const rewardAmount = baseRewardAmount * BigInt(i + 1);
        await expect(tx).to.changeTokenBalances(testTokens[i], [alice, rewarder], [rewardAmount, -rewardAmount]);
      }
    });
  });
});
