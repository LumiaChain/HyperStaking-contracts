import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { parseEther, ZeroAddress } from "ethers";

import * as shared from "./shared";

describe("Lockbox", function () {
  async function deployHyperStaking() {
    const [owner, stakingManager, strategyVaultManager, bob, alice] = await ethers.getSigners();

    const {
      mailbox, interchainFactory, diamond, staking, factory, tier1, tier2, lockbox,
    } = await shared.deployTestHyperStaking(0n);

    // --------------------- Deploy Tokens ----------------------

    const testReserveAsset = await shared.deloyTestERC20("Test Reserve Asset", "tRaETH");

    // ------------------ Create Staking Pools ------------------

    const { nativeTokenAddress, ethPoolId } = await shared.createNativeStakingPool(staking);

    // -------------------- Apply Strategies --------------------

    const defaultRevenueFee = parseEther("0"); // 0% fee

    // strategy asset price to eth 2:1
    const reserveAssetPrice = parseEther("2");

    const reserveStrategy = await shared.createReserveStrategy(
      diamond, nativeTokenAddress, await testReserveAsset.getAddress(), reserveAssetPrice,
    );

    await factory.connect(strategyVaultManager).addStrategy(
      ethPoolId,
      reserveStrategy,
      testReserveAsset,
      defaultRevenueFee,
    );

    // set fee after strategy is added
    const mailboxFee = parseEther("0.05");
    await mailbox.connect(owner).setFee(mailboxFee);

    const vaultTokenAddress = (await tier2.vaultTier2Info(reserveStrategy)).vaultToken;
    const vaultToken = await ethers.getContractAt("VaultToken", vaultTokenAddress);

    const lpTokenAddress = await interchainFactory.lpTokens(vaultTokenAddress);
    const lpToken = await ethers.getContractAt("LumiaLPToken", lpTokenAddress);

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, factory, tier1, tier2, lockbox, // diamond facets
      mailbox, interchainFactory, testReserveAsset, reserveStrategy, vaultToken, lpToken, // test contracts
      ethPoolId, // ids
      defaultRevenueFee, reserveAssetPrice, mailboxFee, // values
      nativeTokenAddress, owner, stakingManager, strategyVaultManager, alice, bob, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("Lockbox", function () {
    it("stake deposit to tier2 with non-zero mailbox fee", async function () {
      const {
        staking, ethPoolId, reserveStrategy, vaultToken, lpToken, mailboxFee, owner, alice,
      } = await loadFixture(deployHyperStaking);

      const lpBefore = await lpToken.balanceOf(alice);

      const stakeAmount = parseEther("2");

      const tier2 = 2;
      await expect(staking.stakeDepositTier2(
        ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount + mailboxFee },
      ))
        .to.emit(staking, "StakeDeposit")
        .withArgs(owner, alice, ethPoolId, reserveStrategy, stakeAmount, tier2);

      const lpAfter = await lpToken.balanceOf(alice);
      expect(lpAfter).to.be.gt(lpBefore);

      // more accurate amount calculation
      const allocation = await reserveStrategy.convertToAllocation(stakeAmount);
      const lpAmount = await vaultToken.previewDeposit(allocation);

      expect(lpAfter).to.be.eq(lpBefore + lpAmount);

      // stake values should be 0 in tier2
      expect((await staking.userPoolInfo(ethPoolId, alice)).stakeLocked).to.equal(0);
      expect((await staking.poolInfo(ethPoolId)).totalStake).to.equal(0);
    });

    it("mailbox fee is needed when adding strategy too", async function () {
      const {
        diamond, staking, factory, lockbox, mailboxFee, strategyVaultManager,
      } = await loadFixture(deployHyperStaking);

      // new pool and strategy
      const { nativeTokenAddress, ethPoolId } = await shared.createNativeStakingPool(staking);
      const asset2 = await shared.deloyTestERC20("Test Reserve Asset 2", "t2");

      const strategy2 = await shared.createReserveStrategy(
        diamond, nativeTokenAddress, await asset2.getAddress(), parseEther("1"),
      );

      // revert if mailbox fee is not sent
      await expect(factory.connect(strategyVaultManager).addStrategy(
        ethPoolId,
        strategy2,
        asset2,
        0n,
      )).to.be.reverted;

      expect( // in a real scenario fee could depend on the token address, correct name and symbol
        await lockbox.quoteDispatchTokenDeploy(ZeroAddress, "Test Reserve Asset 2", "t2"),
      ).to.equal(mailboxFee);

      await factory.connect(strategyVaultManager).addStrategy(
        ethPoolId,
        strategy2,
        asset2,
        0n,
        { value: mailboxFee },
      );
    });
  });

  // TODO test HyperlaneMessages:
  // require(temp.length <= 32, "stringToBytes32: overflow");
  // require(temp.length <= 64, "stringToBytes64: overflow");
});
