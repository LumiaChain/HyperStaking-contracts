import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { parseEther, parseUnits } from "ethers";

import * as shared from "./shared";

describe("VaultToken", function () {
  async function deployHyperStaking() {
    const [owner, stakingManager, strategyVaultManager, bob, alice] = await ethers.getSigners();

    const { interchainFactory, diamond, staking, factory, tier1, tier2 } = await shared.deployTestHyperStaking(0n);

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

    const vaultTokenAddress = (await tier2.vaultTier2Info(reserveStrategy)).vaultToken;
    const vaultToken = await ethers.getContractAt("VaultToken", vaultTokenAddress);

    const lpTokenAddress = await interchainFactory.lpTokens(vaultTokenAddress);
    const lpToken = await ethers.getContractAt("LumiaLPToken", lpTokenAddress);

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, factory, tier1, tier2, interchainFactory, // diamond facets
      testReserveAsset, reserveStrategy, vaultToken, lpToken, // test contracts
      ethPoolId, // ids
      defaultRevenueFee, reserveAssetPrice, // values
      nativeTokenAddress, owner, stakingManager, strategyVaultManager, alice, bob, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("Tier2", function () {
    it("it shouldn't be possible to mint shares apart from the diamond", async function () {
      const { vaultToken, alice } = await loadFixture(deployHyperStaking);

      await expect(vaultToken.deposit(100, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");

      await expect(vaultToken.mint(100, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");
    });

    it("it should be possible to stake deposit to tier2", async function () {
      const { staking, ethPoolId, reserveStrategy, vaultToken, lpToken, owner, alice } = await loadFixture(deployHyperStaking);

      const lpBefore = await lpToken.balanceOf(alice);

      const stakeAmount = parseEther("6");

      const tier2 = 2;
      await expect(staking.stakeDepositTier2(
        ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount },
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

    it("shars should be minted equally regardless of the deposit order", async function () {
      const { staking, ethPoolId, reserveStrategy, vaultToken, owner, alice, bob } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("7");

      await staking.stakeDepositTier2(ethPoolId, reserveStrategy, stakeAmount, owner, { value: stakeAmount });
      await staking.stakeDepositTier2(ethPoolId, reserveStrategy, stakeAmount, bob, { value: stakeAmount });
      await staking.stakeDepositTier2(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      const aliceShares = await vaultToken.balanceOf(alice);
      const bobShares = await vaultToken.balanceOf(bob);
      const ownerShares = await vaultToken.balanceOf(owner);

      expect(aliceShares).to.be.eq(bobShares);
      expect(aliceShares).to.be.eq(ownerShares);

      // 2x stake
      await staking.stakeDepositTier2(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      const aliceShares2 = await vaultToken.balanceOf(alice);
      expect(aliceShares2).to.be.eq(2n * bobShares);
    });

    it("it should be possible to approve and transfer lpTokens", async function () {
      const { staking, ethPoolId, reserveStrategy, lpToken, owner, alice, bob } = await loadFixture(deployHyperStaking);

      expect(await lpToken.balanceOf(alice)).to.be.eq(0);
      expect(await lpToken.balanceOf(bob)).to.be.eq(0);
      expect(await lpToken.balanceOf(owner)).to.be.eq(0);

      const stakeAmount = parseEther("3");
      await staking.stakeDepositTier2(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });
      const lpBalance = await lpToken.balanceOf(alice);

      await lpToken.connect(alice).approve(bob, lpBalance);
      await lpToken.connect(bob).transferFrom(alice, bob, lpBalance);

      expect(await lpToken.balanceOf(alice)).to.be.eq(0);
      expect(await lpToken.balanceOf(bob)).to.be.eq(lpBalance);
      expect(await lpToken.balanceOf(owner)).to.be.eq(0);

      await lpToken.connect(bob).transfer(owner, lpBalance);

      expect(await lpToken.balanceOf(alice)).to.be.eq(0);
      expect(await lpToken.balanceOf(bob)).to.be.eq(0);
      expect(await lpToken.balanceOf(owner)).to.be.eq(lpBalance);

      await staking.stakeDepositTier2(ethPoolId, reserveStrategy, stakeAmount, bob, { value: stakeAmount });
      await staking.stakeDepositTier2(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });
    });

    it("it should be possible to redeem vaultToken and withdraw stake", async function () {
      const {
        staking, ethPoolId, testReserveAsset, reserveStrategy, interchainFactory,
        reserveAssetPrice, vaultToken, lpToken, alice, bob,
      } = await loadFixture(deployHyperStaking);

      expect(await vaultToken.balanceOf(alice)).to.be.eq(0);
      expect(await lpToken.balanceOf(alice)).to.be.eq(0);

      const stakeAmount = parseEther("3");
      await staking.stakeDepositTier2(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      const lpBalance = await lpToken.balanceOf(alice);

      expect(await lpToken.balanceOf(alice)).to.be.gt(0);
      expect(await vaultToken.totalAssets()).to.be.eq(stakeAmount * parseEther("1") / reserveAssetPrice);
      expect(await testReserveAsset.balanceOf(vaultToken)).to.be.gt(0);

      // redeem should be possible only through tier2 - proxy
      await expect(vaultToken.connect(alice).redeem(lpBalance, alice, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");

      // withdraw should be possible only through tier2 - proxy
      await expect(vaultToken.connect(alice).withdraw(stakeAmount, alice, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");

      // interchain redeem
      await lpToken.connect(alice).approve(interchainFactory, lpBalance);
      const dispatchFee = await interchainFactory.quoteDispatchTokenRedeem(vaultToken, bob, lpBalance);
      await interchainFactory.connect(alice).redeemLpTokensDispatch(
        lpToken, alice, lpBalance, { value: dispatchFee },
      );

      expect(await vaultToken.balanceOf(alice)).to.be.eq(0);
      expect(await lpToken.balanceOf(alice)).to.be.eq(0);
      expect(await testReserveAsset.balanceOf(vaultToken)).to.be.eq(0);

      // -- scenario with approval redeem
      await staking.stakeDepositTier2(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      // alice approve factory and bob excutes redeem for her
      await lpToken.connect(alice).approve(interchainFactory, lpBalance);
      await interchainFactory.connect(bob).redeemLpTokensDispatch(
        lpToken, alice, lpBalance, { value: dispatchFee },
      );

      expect(await vaultToken.allowance(alice, bob)).to.be.eq(0);
      expect(await vaultToken.balanceOf(alice)).to.be.eq(0);
      expect(await vaultToken.balanceOf(bob)).to.be.eq(0);
      expect(await testReserveAsset.balanceOf(vaultToken)).to.be.eq(0);
    });

    it("fee from tier1 should increase tier2 shares value", async function () {
      const {
        staking, tier1, tier2, interchainFactory, ethPoolId, reserveStrategy, vaultToken, lpToken,
        strategyVaultManager, alice, bob,
      } = await loadFixture(deployHyperStaking);

      const price1 = parseEther("2");
      const price2 = parseEther("4");
      const priceRatio = price2 / price1;

      await reserveStrategy.setAssetPrice(price1);

      const revenueFee = parseUnits("20", 16); // 20% fee
      tier1.connect(strategyVaultManager).setRevenueFee(reserveStrategy, revenueFee);

      expect(await vaultToken.totalAssets()).to.be.eq(0);

      const aliceStakeAmount = parseEther("10");
      const bobStakeAmount = parseEther("1");

      // alice stake to tier1, bob stake to tier2
      await staking.stakeDeposit(ethPoolId, reserveStrategy, aliceStakeAmount, alice, { value: aliceStakeAmount });
      await staking.stakeDepositTier2(ethPoolId, reserveStrategy, bobStakeAmount, bob, { value: bobStakeAmount });

      await reserveStrategy.setAssetPrice(price2);

      let expectedBobAllocation = bobStakeAmount * parseEther("1") / price1;
      const expectedBobShares = expectedBobAllocation;

      expect(await vaultToken.totalAssets()).to.be.eq(expectedBobAllocation);
      expect((await tier2.sharesTier2Info(reserveStrategy, expectedBobShares)).shares).to.be.eq(expectedBobShares);
      expect((await tier2.sharesTier2Info(reserveStrategy, expectedBobShares)).allocation).to.be.eq(expectedBobAllocation);
      expect((await tier2.sharesTier2Info(reserveStrategy, expectedBobShares)).stake).to.be.eq(bobStakeAmount * priceRatio);

      expect(await vaultToken.totalAssets()).to.be.eq(expectedBobAllocation);

      // Tier1 withdraw generates fee
      await staking.connect(alice).stakeWithdraw(ethPoolId, reserveStrategy, aliceStakeAmount, alice);

      const allocationFee = await tier1.allocationFee(
        reserveStrategy,
        await tier1.allocationGain(reserveStrategy, alice, aliceStakeAmount),
      );

      // shares amount does not change, but allocation should increase
      expectedBobAllocation += allocationFee;

      const precisionError = 1n;
      const expectedNewBobStake = await reserveStrategy.convertToStake(expectedBobAllocation - precisionError);

      expect(await vaultToken.totalAssets()).to.be.eq(expectedBobAllocation);
      expect((await tier2.sharesTier2Info(reserveStrategy, expectedBobShares)).shares).to.be.eq(expectedBobShares);
      expect((await tier2.sharesTier2Info(reserveStrategy, expectedBobShares)).allocation).to.be.eq(expectedBobAllocation - precisionError);
      expect((await tier2.sharesTier2Info(reserveStrategy, expectedBobShares)).stake).to.be.eq(expectedNewBobStake);

      // actual withdraw -> redeem of lpTokens
      await lpToken.connect(bob).approve(interchainFactory, expectedBobShares);
      const dispatchFee = await interchainFactory.quoteDispatchTokenRedeem(vaultToken, bob, expectedBobShares);
      await expect(interchainFactory.connect(bob).redeemLpTokensDispatch(
        lpToken, bob, expectedBobShares, { value: dispatchFee },
      ))
        .to.changeEtherBalance(bob, expectedNewBobStake);

      expect(await vaultToken.totalSupply()).to.be.eq(0);
      expect(await vaultToken.totalAssets()).to.be.eq(precisionError);
    });

    it("it should be possible to effectively migrate from tier1 to tier2", async function () {
      const {
        staking, tier1, tier2, ethPoolId, reserveStrategy, testReserveAsset, vaultToken, lpToken,
        interchainFactory, strategyVaultManager, alice,
      } = await loadFixture(deployHyperStaking);

      const price1 = parseEther("1");
      const price2 = parseEther("1.5");

      await reserveStrategy.setAssetPrice(price1);

      const revenueFee = parseUnits("10", 16); // 10% fee
      tier1.connect(strategyVaultManager).setRevenueFee(reserveStrategy, revenueFee);

      const stakeAmount = parseEther("10");

      // alice stake to tier1
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      await reserveStrategy.setAssetPrice(price2);

      // is should not be possible to migrate more than staked
      await expect(tier1.connect(alice).migrateToTier2(reserveStrategy, stakeAmount + 1n))
        .to.be.revertedWithCustomError(tier1, "InsufficientStakeLocked");

      const allocationFee = await tier1.allocationFee(
        reserveStrategy,
        await tier1.allocationGain(reserveStrategy, alice, stakeAmount),
      );

      await tier1.connect(alice).migrateToTier2(reserveStrategy, stakeAmount);

      // check Tier1 values
      expect((await tier1.userTier1Info(reserveStrategy, alice)).stakeLocked).to.equal(0);
      expect((await tier1.vaultTier1Info(reserveStrategy)).assetAllocation).to.equal(0);
      expect((await tier1.vaultTier1Info(reserveStrategy)).totalStakeLocked).to.equal(0);

      // assets
      expect(await ethers.provider.getBalance(staking)).to.equal(0);
      expect(await testReserveAsset.balanceOf(tier1)).to.equal(0);
      expect(await testReserveAsset.balanceOf(vaultToken)).to.equal(stakeAmount);
      expect(await vaultToken.totalAssets()).to.be.eq(stakeAmount);

      // staking
      expect((await staking.userPoolInfo(ethPoolId, alice)).staked).to.equal(0);
      expect((await staking.userPoolInfo(ethPoolId, alice)).stakeLocked).to.equal(0);
      expect((await staking.poolInfo(ethPoolId)).totalStake).to.equal(0);

      // check Tier2 shares
      const shares = await vaultToken.convertToShares(stakeAmount - allocationFee); // assume price == 1
      const allocation = await vaultToken.convertToAssets(shares);
      const expectedStake = allocation * price2 / parseEther("1");

      expect(await vaultToken.totalSupply()).to.be.eq(shares);
      expect((await tier2.sharesTier2Info(reserveStrategy, shares)).shares).to.be.eq(shares);
      expect((await tier2.sharesTier2Info(reserveStrategy, shares)).allocation).to.be.eq(allocation);
      expect((await tier2.sharesTier2Info(reserveStrategy, shares)).stake).to.be.eq(expectedStake);

      // expectedStake is lower than it would be if deposited directly into tier2
      expect(expectedStake).to.be.lt((stakeAmount) * price2 / parseEther("1"));

      // redeem
      await lpToken.connect(alice).approve(interchainFactory, shares);
      const dispatchFee = await interchainFactory.quoteDispatchTokenRedeem(vaultToken, alice, shares);
      await expect(interchainFactory.connect(alice).redeemLpTokensDispatch(
        lpToken, alice, shares, { value: dispatchFee },
      ))
        .to.changeEtherBalances([alice], [expectedStake]);
    });
  });
});
