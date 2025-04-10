import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { Addressable, Contract, parseEther, parseUnits, ZeroAddress } from "ethers";

import * as shared from "./shared";

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testUSDC = await shared.deloyTestERC20("Test USDC", "tUSDC", 6); // 6 decimal places
  const erc4626Vault = await shared.deloyTestERC4626Vault(testUSDC);

  // --------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Add Tokens Rewarder --------------------

  const tokensRewarder = await ethers.deployContract("TokensRewarder", [hyperStaking.lumiaDiamond, hyperStaking.rwaUSD]);
  await hyperStaking.masterChef.connect(signers.lumiaRewardManager).set(hyperStaking.rwaUSD, tokensRewarder);

  // ----------------------------------------

  await hyperStaking.rwaUSDOwner.addMinter(signers.owner);
  await hyperStaking.rwaUSDOwner.mint(signers.owner, parseUnits("1000000", 6));
  await hyperStaking.rwaUSDOwner.mint(signers.alice, parseUnits("1000000", 6));
  await hyperStaking.rwaUSDOwner.mint(signers.bob, parseUnits("1000000", 6));

  const REWARD_PRECISION = await tokensRewarder.REWARD_PRECISION();
  const REWARDS_PER_STAKING_LIMIT = await tokensRewarder.REWARDS_PER_STAKING_LIMIT();

  // ----------------------------------------

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    testUSDC, tokensRewarder, // test contracts
    REWARD_PRECISION, REWARDS_PER_STAKING_LIMIT, // const
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

async function deployTestTokens(to: Addressable) {
  const testTokens: Contract[] = [];

  // deploy test tokens
  for (let i = 1; i <= 11; i++) {
    const name = `TestToken${i}`;
    const symbol = `tt${i}`;
    const token = await shared.deloyTestERC20(name, symbol);
    token.mint(to, parseEther("1000000"));
    testTokens.push(token);
  }

  return { testTokens };
}

describe("TokensRewarder", function () {
  describe("Reward distribution", function () {
    it("Empty rewarder values", async function () {
      const { tokensRewarder, signers } = await loadFixture(deployHyperStaking);
      const { alice, lumiaRewardManager } = signers;

      const badRewardIdx = 0;
      expect(await tokensRewarder.isRewardActive(badRewardIdx)).to.be.eq(false);
      expect(await tokensRewarder.getActiveRewardList()).to.be.deep.eq([]);

      // these function should not revert even if there are no rewarders
      await expect(tokensRewarder.updateActivePools(ZeroAddress)).not.to.be.reverted;
      await expect(tokensRewarder.updateActivePools(alice)).not.to.be.reverted;
      await expect(tokensRewarder.claimAll(alice)).not.to.be.reverted;

      // but specific reward throw "not found"
      await expect(tokensRewarder.claimReward(badRewardIdx, alice))
        .to.be.revertedWithCustomError(tokensRewarder, "RewardNotFound");

      await expect(tokensRewarder.updatePool(badRewardIdx))
        .to.be.revertedWithCustomError(tokensRewarder, "RewardNotFound");

      await expect(tokensRewarder.updateUser(badRewardIdx, alice))
        .to.be.revertedWithCustomError(tokensRewarder, "RewardNotFound");

      await expect(tokensRewarder.pendingReward(badRewardIdx, alice))
        .to.be.revertedWithCustomError(tokensRewarder, "RewardNotFound");

      await expect(tokensRewarder.userRewardInfo(badRewardIdx, alice))
        .to.be.revertedWithCustomError(tokensRewarder, "RewardNotFound");

      await expect(tokensRewarder.rewardInfo(badRewardIdx))
        .to.be.revertedWithCustomError(tokensRewarder, "RewardNotFound");

      await expect(tokensRewarder.balance(badRewardIdx))
        .to.be.revertedWithCustomError(tokensRewarder, "RewardNotFound");

      await expect(tokensRewarder.rewardPool(badRewardIdx))
        .to.be.revertedWithCustomError(tokensRewarder, "RewardNotFound");

      await expect(tokensRewarder.connect(lumiaRewardManager).finalize(badRewardIdx))
        .to.be.revertedWithCustomError(tokensRewarder, "RewardNotFound");
    });

    it("Only LumiaRewardManager should be able to execute protected fucntions", async function () {
      const { hyperStaking, tokensRewarder } = await loadFixture(deployHyperStaking);
      const rewardToken = hyperStaking.rwaUSD;

      const rewardAmount = parseEther("100");
      await rewardToken.approve(tokensRewarder, rewardAmount);

      const startTimestamp = await shared.getCurrentBlockTimestamp() + 100;
      await time.setNextBlockTimestamp(startTimestamp);
      const distributionEnd = startTimestamp + 1000;

      await expect(tokensRewarder.newRewardDistribution(
        rewardToken,
        rewardAmount,
        0, // - now (startTimestamp)
        distributionEnd,
      )).to.be.revertedWithCustomError(tokensRewarder, "NotLumiaRewardManager");

      await expect(tokensRewarder.notifyRewardDistribution(
        0,
        rewardAmount,
        0, // - now (startTimestamp)
        distributionEnd,
      )).to.be.revertedWithCustomError(tokensRewarder, "NotLumiaRewardManager");

      await expect(tokensRewarder.finalizeAll())
        .to.be.revertedWithCustomError(tokensRewarder, "NotLumiaRewardManager");

      await expect(tokensRewarder.finalize(0))
        .to.be.revertedWithCustomError(tokensRewarder, "NotLumiaRewardManager");

      await expect(tokensRewarder.withdrawRemaining(0, ZeroAddress))
        .to.be.revertedWithCustomError(tokensRewarder, "NotLumiaRewardManager");
    });

    it("Create new reward distribution", async function () {
      const { tokensRewarder, signers } = await loadFixture(deployHyperStaking);
      const { lumiaRewardManager } = signers;
      const { testTokens } = await deployTestTokens(lumiaRewardManager);
      const rewardToken = testTokens[0];

      const rewardAmount = parseEther("100");
      await rewardToken.connect(lumiaRewardManager).approve(tokensRewarder, rewardAmount);

      const startTimestamp = await shared.getCurrentBlockTimestamp() + 100;
      await time.setNextBlockTimestamp(startTimestamp);
      const distributionEnd = startTimestamp + 1000;

      const rewardIdx = 0;
      await expect(tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
        rewardToken,
        rewardAmount,
        0, // - now (startTimestamp)
        distributionEnd,
      )).to.emit(tokensRewarder, "RewardNotify")
        .withArgs(lumiaRewardManager, rewardToken, rewardIdx, rewardAmount, 0, startTimestamp, distributionEnd, true);

      const rewardPool = await tokensRewarder.rewardPool(rewardIdx);
      expect(rewardPool.tokensPerSecond).to.eq(rewardAmount * parseUnits("1", 36) / BigInt(distributionEnd - startTimestamp));
    });

    it("Reward creation should revert in some cases", async function () {
      const { hyperStaking, tokensRewarder, signers } = await loadFixture(deployHyperStaking);
      const { lumiaRewardManager } = signers;
      const rewardToken = hyperStaking.rwaUSD;

      await expect(tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
        ZeroAddress,
        0,
        0,
        0,
      )).to.be.revertedWithCustomError(tokensRewarder, "TokenZeroAddress");

      let startTimestamp = await shared.getCurrentBlockTimestamp() - 100;

      await expect(tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
        rewardToken,
        0,
        startTimestamp,
        0,
      )).to.be.revertedWithCustomError(tokensRewarder, "StartTimestampPassed");

      startTimestamp = await shared.getCurrentBlockTimestamp() + 100;

      await expect(tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
        rewardToken,
        0,
        startTimestamp,
        startTimestamp,
      )).to.be.revertedWithCustomError(tokensRewarder, "InvalidDistributionRange");

      const rewardAmount = parseUnits("1", 30) + 1n;

      await expect(tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
        rewardToken,
        rewardAmount, // too big value
        startTimestamp,
        startTimestamp + 1, // 1 second distribution
      )).to.be.revertedWithCustomError(tokensRewarder, "RateTooHigh");
    });

    it("Reward shouldn't be distribute after its end", async function () {
      const { hyperStaking, tokensRewarder, REWARD_PRECISION, signers } = await loadFixture(deployHyperStaking);
      const { masterChef, rwaUSD } = hyperStaking;
      const { alice, lumiaRewardManager } = signers;

      const { testTokens } = await deployTestTokens(lumiaRewardManager);
      const stakeToken = rwaUSD;
      const rewardToken = testTokens[0];

      const rewardIdx = 0;
      const rewardAmount = parseEther("100");
      await rewardToken.connect(lumiaRewardManager).approve(tokensRewarder, rewardAmount);

      const stakeAmount = parseUnits("1", 6);
      await stakeToken.connect(alice).approve(masterChef, stakeAmount);
      await masterChef.connect(alice).stake(stakeToken, stakeAmount);

      const startTimestamp = await shared.getCurrentBlockTimestamp() + 100;
      const distributionDuration = 1000; // seconds
      const distributionEnd = startTimestamp + distributionDuration;

      await time.setNextBlockTimestamp(startTimestamp);

      // notify when there are no stakers yet
      await tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
        rewardToken,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      );

      await time.increase(distributionDuration);

      // the whole reward
      expect(await tokensRewarder.pendingReward(rewardIdx, alice)).to.eq(rewardAmount);

      // update pool to check userRewardInfo
      await tokensRewarder.updatePool(rewardIdx);
      await tokensRewarder.updateUser(rewardIdx, alice);

      const expectedRewardPerTokenPaid = rewardAmount * REWARD_PRECISION / stakeAmount;

      // info before claim
      let userRewardInfo = await tokensRewarder.userRewardInfo(rewardIdx, alice);
      expect(userRewardInfo.rewardPerTokenPaid).to.eq(expectedRewardPerTokenPaid);

      await expect(tokensRewarder.connect(alice).claimReward(rewardIdx, alice))
        .to.changeTokenBalances(rewardToken,
          [alice, tokensRewarder],
          [rewardAmount, -rewardAmount],
        );

      // info after claim
      userRewardInfo = await tokensRewarder.userRewardInfo(rewardIdx, alice);
      expect(userRewardInfo.rewardPerTokenPaid).to.eq(expectedRewardPerTokenPaid);
      expect(userRewardInfo.rewardUnclaimed).to.eq(0);

      expect(await tokensRewarder.pendingReward(rewardIdx, alice)).to.eq(0);

      // withdraw should work as expected
      await expect(masterChef.connect(alice).withdraw(stakeToken, stakeAmount))
        .to.changeTokenBalances(stakeToken,
          [alice, masterChef],
          [stakeAmount, -stakeAmount],
        );

      // info after withdraw
      userRewardInfo = await tokensRewarder.userRewardInfo(rewardIdx, alice);
      expect(userRewardInfo.rewardPerTokenPaid).to.eq(expectedRewardPerTokenPaid);
      expect(userRewardInfo.rewardUnclaimed).to.eq(0);
    });

    it("Reward should be applied to current stakers too", async function () {
      const { hyperStaking, tokensRewarder, REWARD_PRECISION, signers } = await loadFixture(deployHyperStaking);
      const { masterChef, rwaUSD } = hyperStaking;
      const { alice, lumiaRewardManager } = signers;

      const { testTokens } = await deployTestTokens(lumiaRewardManager);
      const stakeToken = rwaUSD;
      const rewardToken = testTokens[0];

      const rewardIdx = 0;
      const rewardAmount = parseEther("50");
      await rewardToken.connect(lumiaRewardManager).approve(tokensRewarder, rewardAmount);

      const stakeAmount = parseUnits("1", 6);
      await stakeToken.connect(alice).approve(masterChef, stakeAmount);
      await masterChef.connect(alice).stake(stakeToken, stakeAmount);

      const startTimestamp = await shared.getCurrentBlockTimestamp() + 100;
      const distributionDuration = 10000; // seconds
      const distributionEnd = startTimestamp + distributionDuration;
      await time.setNextBlockTimestamp(startTimestamp);

      // notify when there are already stakers
      await tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
        rewardToken,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      );

      await time.increase(distributionDuration);

      const rewardPool = await tokensRewarder.rewardPool(rewardIdx);
      expect(rewardPool.tokensPerSecond).to.eq(rewardAmount * REWARD_PRECISION / BigInt(distributionDuration));
      expect(rewardPool.rewardPerToken).to.eq(0);
      expect(rewardPool.lastRewardTimestamp).to.eq(startTimestamp);

      // reward should be counted even if the user did not stake after notify
      expect(await tokensRewarder.pendingReward(rewardIdx, alice)).to.eq(rewardAmount);

      // info before claim
      let userRewardInfo = await tokensRewarder.userRewardInfo(rewardIdx, alice);
      expect(userRewardInfo.rewardPerTokenPaid).to.eq(0);
      expect(userRewardInfo.rewardUnclaimed).to.eq(0);

      await expect(tokensRewarder.connect(alice).claimAll(alice))
        .to.changeTokenBalances(rewardToken,
          [alice, tokensRewarder],
          [rewardAmount, -rewardAmount],
        );

      // withdraw should work as expected
      await expect(masterChef.connect(alice).withdraw(stakeToken, stakeAmount))
        .to.changeTokenBalances(stakeToken,
          [alice, masterChef],
          [stakeAmount, -stakeAmount],
        );

      // claim after withdraw should work too
      expect(await tokensRewarder.pendingReward(rewardIdx, alice)).to.eq(0);

      // info after withdraw
      userRewardInfo = await tokensRewarder.userRewardInfo(rewardIdx, alice);
      expect(userRewardInfo.rewardPerTokenPaid).to.eq(rewardAmount * REWARD_PRECISION / stakeAmount);
      expect(userRewardInfo.rewardUnclaimed).to.eq(0);
    });

    it("Check calculations for more than one staker", async function () {
      const { hyperStaking, tokensRewarder, signers } = await loadFixture(deployHyperStaking);
      const { masterChef, rwaUSD } = hyperStaking;
      const { alice, bob, lumiaRewardManager } = signers;

      const { testTokens } = await deployTestTokens(lumiaRewardManager);
      const stakeToken = rwaUSD;
      const rewardToken = testTokens[0];

      const rewardIdx = 0;
      const rewardAmount = parseEther("6000");
      await rewardToken.connect(lumiaRewardManager).approve(tokensRewarder, rewardAmount);

      // alice stakes first
      const stakeAmount = parseUnits("1", 6);
      await stakeToken.connect(alice).approve(masterChef, stakeAmount);
      await masterChef.connect(alice).stake(stakeToken, stakeAmount);

      const startTimestamp = await shared.getCurrentBlockTimestamp() + 100;
      const distributionDuration = 20000; // seconds
      const distributionEnd = startTimestamp + distributionDuration;
      await time.setNextBlockTimestamp(startTimestamp);

      // notify when there are already stakers
      await tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
        rewardToken,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      );

      expect(await tokensRewarder.pendingReward(rewardIdx, alice)).to.eq(0);
      expect(await tokensRewarder.pendingReward(rewardIdx, bob)).to.eq(0);

      // 1/2 of the distributionDuration
      await time.increase(distributionDuration / 2 - 2);

      // bob enters with the same stake as alice
      await stakeToken.connect(bob).approve(masterChef, stakeAmount);
      await masterChef.connect(bob).stake(stakeToken, stakeAmount);

      expect(await tokensRewarder.pendingReward(rewardIdx, alice)).to.eq(rewardAmount / 2n);
      expect(await tokensRewarder.pendingReward(rewardIdx, bob)).to.eq(0);

      // finish distribution
      await time.increase(distributionDuration / 2 + 2);

      // alice should get around 3/4 and bob 1/4 of the reward
      expect(await tokensRewarder.pendingReward(rewardIdx, alice)).to.eq(rewardAmount * 3n / 4n);
      expect(await tokensRewarder.pendingReward(rewardIdx, bob)).to.eq(rewardAmount / 4n);

      await expect(tokensRewarder.connect(alice).claimReward(rewardIdx, alice))
        .to.changeTokenBalances(rewardToken,
          [alice, tokensRewarder],
          [rewardAmount * 3n / 4n, -rewardAmount * 3n / 4n],
        );

      await expect(tokensRewarder.connect(bob).claimAll(bob))
        .to.changeTokenBalances(rewardToken,
          [bob, tokensRewarder],
          [rewardAmount / 4n, -rewardAmount / 4n],
        );
    });

    it("Extending reward distribution should be possible, leftover", async function () {
      const { hyperStaking, tokensRewarder, signers } = await loadFixture(deployHyperStaking);
      const { masterChef, rwaUSD } = hyperStaking;
      const { alice, bob, lumiaRewardManager } = signers;

      const { testTokens } = await deployTestTokens(lumiaRewardManager);
      const stakeToken = rwaUSD;
      const rewardToken = testTokens[0];

      const rewardIdx = 0;
      const rewardAmount1 = parseEther("2000");
      const rewardAmount2 = parseEther("4000");
      await rewardToken.connect(lumiaRewardManager).approve(tokensRewarder, rewardAmount1);

      // alice stakes
      const stakeAmount = parseUnits("1", 6);
      await stakeToken.connect(alice).approve(masterChef, stakeAmount);
      await masterChef.connect(alice).stake(stakeToken, stakeAmount);

      const startTimestamp = await shared.getCurrentBlockTimestamp() + 100;
      const distributionDuration = 2000; // seconds
      const distributionEnd = startTimestamp + distributionDuration;
      await time.setNextBlockTimestamp(startTimestamp);

      // notify rewardAmount1
      await tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
        rewardToken,
        rewardAmount1,
        startTimestamp,
        distributionEnd,
      );

      expect(await tokensRewarder.pendingReward(rewardIdx, alice)).to.eq(0);
      expect(await tokensRewarder.pendingReward(rewardIdx, bob)).to.eq(0);

      // 1/2 of the distributionDuration
      await time.increase(distributionDuration / 2 - 2);

      // bob stakes
      await stakeToken.connect(bob).approve(masterChef, stakeAmount);
      await masterChef.connect(bob).stake(stakeToken, stakeAmount);

      expect(await tokensRewarder.pendingReward(rewardIdx, alice)).to.eq(rewardAmount1 / 2n);
      expect(await tokensRewarder.pendingReward(rewardIdx, bob)).to.eq(0);

      // notify second reward distribution when first didnt finish yet - rewardAmount2
      await rewardToken.connect(lumiaRewardManager).approve(tokensRewarder, rewardAmount2);
      await tokensRewarder.connect(lumiaRewardManager).notifyRewardDistribution(
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
      expect(await tokensRewarder.pendingReward(rewardIdx, alice))
        .to.eq(expectedAliceReward - precisionError);
      expect(await tokensRewarder.pendingReward(rewardIdx, bob))
        .to.eq(expectedBobReward - precisionError);

      // ------------------------------

      // lets notifu a new distribution after some time has passed
      await time.increase(distributionDuration * 5);

      const rewardAmount3 = parseEther("10000");
      await rewardToken.connect(lumiaRewardManager).approve(tokensRewarder, rewardAmount3);

      const start3 = await time.latest() + 1;
      const duration3 = 100; // seconds
      const end3 = start3 + duration3;
      await time.setNextBlockTimestamp(start3);

      // notify rewardAmount3
      await tokensRewarder.connect(lumiaRewardManager).notifyRewardDistribution(
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

      expect(await tokensRewarder.pendingReward(rewardIdx, alice))
        .to.eq(expectedAliceReward - precisionError);
      expect(await tokensRewarder.pendingReward(rewardIdx, bob))
        .to.eq(expectedBobReward - precisionError);

      // claims

      await expect(tokensRewarder.connect(alice).claimAll(alice))
        .to.changeTokenBalances(rewardToken,
          [alice, tokensRewarder],
          [expectedAliceReward - precisionError, -expectedAliceReward + precisionError],
        );

      await expect(tokensRewarder.connect(bob).claimReward(rewardIdx, bob))
        .to.changeTokenBalances(rewardToken,
          [bob, tokensRewarder],
          [expectedBobReward - precisionError, -expectedBobReward + precisionError],
        );
    });

    it("It should be possible to finalize rewarder and claim remaining tokens", async function () {
      const { hyperStaking, tokensRewarder, signers } = await loadFixture(deployHyperStaking);
      const { masterChef, rwaUSD } = hyperStaking;
      const { owner, lumiaRewardManager } = signers;

      const { testTokens } = await deployTestTokens(lumiaRewardManager);
      const stakeToken = rwaUSD;
      const rewardToken = testTokens[0];

      const rewardIdx = 0;
      const rewardAmount = parseEther("6000");
      await rewardToken.connect(lumiaRewardManager).approve(tokensRewarder, rewardAmount);

      const startTimestamp = await time.latest() + 1;
      const distributionDuration = 1500; // seconds
      const distributionEnd = startTimestamp + distributionDuration;
      await time.setNextBlockTimestamp(startTimestamp);

      // notify when there are already stakers
      await tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
        rewardToken,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      );

      expect(await tokensRewarder.getActiveRewardList()).to.be.deep.eq([0]);
      expect(await tokensRewarder.isRewardActive(rewardIdx)).to.be.eq(true);

      const stakeAmount = parseUnits("1", 6);
      await stakeToken.approve(masterChef, stakeAmount);
      await masterChef.stake(stakeToken, stakeAmount);

      await expect(tokensRewarder.connect(lumiaRewardManager).withdrawRemaining(rewardIdx, owner))
        .to.revertedWithCustomError(tokensRewarder, "NotFinalized");

      // finalize in 1/3 of the distributionDuration
      const finalizeTimestamp = startTimestamp + distributionDuration / 3;
      await time.setNextBlockTimestamp(finalizeTimestamp);

      // finalize rewarder
      await expect(tokensRewarder.connect(lumiaRewardManager).finalize(rewardIdx))
        .to.emit(tokensRewarder, "Finalize")
        .withArgs(lumiaRewardManager, rewardToken, rewardIdx, finalizeTimestamp);

      const rewardInfo = await tokensRewarder.rewardInfo(rewardIdx);
      expect(rewardInfo.rewardToken).to.eq(rewardToken);
      expect(rewardInfo.finalizeTimestamp).to.eq(finalizeTimestamp);

      expect(await tokensRewarder.isRewardActive(rewardIdx)).to.be.eq(false);
      const expectedRewarderBalance = rewardAmount * 2n / 3n;
      expect(await tokensRewarder.balance(rewardIdx)).to.eq(expectedRewarderBalance);

      // should not change the withdraw balance
      await time.increase(1000);

      await expect(tokensRewarder.connect(lumiaRewardManager).withdrawRemaining(rewardIdx, owner))
        .to.changeTokenBalances(rewardToken,
          [owner, tokensRewarder],
          [expectedRewarderBalance, -expectedRewarderBalance],
        );

      // should not be possible to notify new distribution on finalized rewarder
      await expect(tokensRewarder.connect(lumiaRewardManager).notifyRewardDistribution(
        rewardIdx,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      )).to.be.revertedWithCustomError(tokensRewarder, "Finalized");
    });
  });

  describe("Concurrent rewards", function () {
    it("multiple rewards limitations", async function () {
      const { tokensRewarder, REWARDS_PER_STAKING_LIMIT, signers } = await loadFixture(deployHyperStaking);
      const { lumiaRewardManager } = signers;

      const { testTokens } = await deployTestTokens(lumiaRewardManager);

      const rewardAmount = parseEther("100");

      const startTimestamp = await time.latest() + 100;
      const distributionEnd = startTimestamp + 1000;

      for (let i = 0; i < REWARDS_PER_STAKING_LIMIT; i++) {
        await testTokens[i].connect(lumiaRewardManager).approve(tokensRewarder, rewardAmount);
        await tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
          testTokens[i],
          rewardAmount,
          startTimestamp,
          distributionEnd,
        );
      }

      await expect(tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
        testTokens[REWARDS_PER_STAKING_LIMIT].target,
        rewardAmount,
        startTimestamp,
        distributionEnd,
      )).to.be.revertedWithCustomError(tokensRewarder, "ActiveRewardsLimitReached");
    });

    it("multiple rewards", async function () {
      const { hyperStaking, tokensRewarder, REWARDS_PER_STAKING_LIMIT, signers } = await loadFixture(deployHyperStaking);
      const { masterChef, rwaUSD } = hyperStaking;
      const { alice, lumiaRewardManager } = signers;

      const { testTokens } = await deployTestTokens(lumiaRewardManager);
      const stakeToken = rwaUSD;

      const stakeAmount = parseUnits("1", 6);
      await stakeToken.connect(alice).approve(masterChef, stakeAmount);
      await masterChef.connect(alice).stake(stakeToken, stakeAmount);

      const baseRewardAmount = parseEther("100");

      const startTimestamp = await time.latest() + 100;
      const distributionDuration = 10000;
      const distributionEnd = startTimestamp + distributionDuration;

      // create many rewards distribution for the same strategy
      for (let i = 0; i < REWARDS_PER_STAKING_LIMIT; i++) {
        const rewardAmount = baseRewardAmount * BigInt(i + 1);
        await testTokens[i].connect(lumiaRewardManager).approve(tokensRewarder, rewardAmount);
        await tokensRewarder.connect(lumiaRewardManager).newRewardDistribution(
          testTokens[i],
          rewardAmount,
          startTimestamp,
          distributionEnd,
        );
      }

      // finish all distributions
      await time.increase(distributionDuration + 100);

      for (let i = 0; i < REWARDS_PER_STAKING_LIMIT; i++) {
        const rewardAmount = baseRewardAmount * BigInt(i + 1);
        expect(await tokensRewarder.pendingReward(i, alice)).to.eq(rewardAmount);
      }

      // claim all rewards
      const tx = tokensRewarder.connect(alice).claimAll(alice);

      for (let i = 0; i < REWARDS_PER_STAKING_LIMIT; i++) {
        const rewardAmount = baseRewardAmount * BigInt(i + 1);
        await expect(tx).to.changeTokenBalances(testTokens[i], [alice, tokensRewarder], [rewardAmount, -rewardAmount]);
      }
    });
  });
});
