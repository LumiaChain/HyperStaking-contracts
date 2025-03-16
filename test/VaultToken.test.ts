import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers, ignition } from "hardhat";
import { parseEther, parseUnits } from "ethers";

import TestRwaAssetModule from "../ignition/modules/test/TestRwaAsset";

import * as shared from "./shared";

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testReserveAsset = await shared.deloyTestERC20("Test Reserve Asset", "tRaETH");
  const erc4626Vault = await shared.deloyTestERC4626Vault(testReserveAsset);

  // -------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Apply Strategies --------------------

  const defaultRevenueFee = parseEther("0"); // 0% fee

  // strategy asset price to eth 2:1
  const reserveAssetPrice = parseEther("2");

  const reserveStrategy = await shared.createReserveStrategy(
    hyperStaking.diamond, shared.nativeTokenAddress, await testReserveAsset.getAddress(), reserveAssetPrice,
  );

  const vaultTokenName = "eth vault1";
  const vaultTokenSymbol = "vETH1";

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    reserveStrategy,
    vaultTokenName,
    vaultTokenSymbol,
    defaultRevenueFee,
    hyperStaking.rwaUSD,
  );

  const vaultTokenAddress = (await hyperStaking.tier2.tier2Info(reserveStrategy)).vaultToken;
  const vaultToken = await ethers.getContractAt("VaultToken", vaultTokenAddress);

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    testReserveAsset, reserveStrategy, vaultToken, // test contracts
    defaultRevenueFee, reserveAssetPrice, vaultTokenName, vaultTokenSymbol, // values
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

describe("VaultToken", function () {
  describe("InterchainFactory", function () {
    it("vault token name, symbol and decimals", async function () {
      const { testReserveAsset, vaultToken, vaultTokenName, vaultTokenSymbol } = await loadFixture(deployHyperStaking);

      expect(await vaultToken.name()).to.equal(vaultTokenName);
      expect(await vaultToken.symbol()).to.equal(vaultTokenSymbol);

      expect(await testReserveAsset.decimals()).to.equal(18);
      expect(await testReserveAsset.decimals()).to.equal(await vaultToken.decimals());
    });

    it("test route and rwaAsset registration", async function () {
      const { hyperStaking, reserveStrategy, signers } = await loadFixture(deployHyperStaking);
      const { diamond, hyperFactory, hyperlaneHandler, realAssets, rwaUSD } = hyperStaking;
      const { vaultManager } = signers;

      const testAsset2 = await shared.deloyTestERC20("Test Asset2", "tRaETH2");
      const testAsset3 = await shared.deloyTestERC20("Test Asset3", "tRaETH3");

      const reserveStrategy2 = await shared.createReserveStrategy(
        diamond, shared.nativeTokenAddress, await testAsset2.getAddress(), parseEther("2"),
      );
      const reserveStrategy3 = await shared.createReserveStrategy(
        diamond, shared.nativeTokenAddress, await testAsset3.getAddress(), parseEther("3"),
      );

      // by adding new stategies more lpTokens should be created
      const { rwaAsset, rwaAssetOwner } = await ignition.deploy(TestRwaAssetModule);
      await rwaAssetOwner.addMinter(realAssets);

      await hyperFactory.connect(vaultManager).addStrategy(
        reserveStrategy2,
        "eth vault2",
        "vETH2",
        0,
        rwaAsset,
      );

      await hyperFactory.connect(vaultManager).addStrategy(
        reserveStrategy3,
        "eth vault3",
        "vETH3",
        0,
        rwaAsset,
      );

      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy)).rwaAsset).to.equal(rwaUSD);
      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy2)).rwaAsset).to.equal(rwaAsset);
      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy3)).rwaAsset).to.equal(rwaAsset);
    });
  });

  describe("Tier2", function () {
    it("it shouldn't be possible to mint shares apart from the diamond", async function () {
      const { vaultToken, signers } = await loadFixture(deployHyperStaking);
      const { alice } = signers;

      await expect(vaultToken.deposit(100, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");

      await expect(vaultToken.mint(100, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");
    });

    it("it should be possible to stake deposit to tier2", async function () {
      const { hyperStaking, reserveStrategy, vaultToken, signers } = await loadFixture(deployHyperStaking);
      const { deposit, tier1, rwaUSD } = hyperStaking;
      const { owner, alice } = signers;

      const stakeAmount = parseEther("6");

      const stakeTypeTier2 = 2;
      await expect(deposit.stakeDepositTier2(
        reserveStrategy, stakeAmount, alice, { value: stakeAmount },
      ))
        .to.emit(deposit, "StakeDeposit")
        .withArgs(owner, alice, reserveStrategy, stakeAmount, stakeTypeTier2);

      const rwaAfter = await rwaUSD.balanceOf(alice);
      expect(rwaAfter).to.be.eq(stakeAmount);

      // shares calculations
      const allocation = await reserveStrategy.previewAllocation(stakeAmount);
      const expectedShares = await vaultToken.previewDeposit(allocation);

      expect(await vaultToken.totalSupply()).to.be.eq(expectedShares);

      // stake values should be 0 in tier1
      expect((await tier1.userTier1Info(reserveStrategy, alice)).stake).to.equal(0);
      expect((await tier1.tier1Info(reserveStrategy)).totalStake).to.equal(0);
    });

    it("shars should be minted equally regardless of the deposit order", async function () {
      const { hyperStaking, reserveStrategy, vaultToken, signers } = await loadFixture(deployHyperStaking);
      const { deposit } = hyperStaking;
      const { owner, alice, bob } = signers;

      const stakeAmount = parseEther("7");

      await deposit.stakeDepositTier2(reserveStrategy, stakeAmount, owner, { value: stakeAmount });
      await deposit.stakeDepositTier2(reserveStrategy, stakeAmount, bob, { value: stakeAmount });
      await deposit.stakeDepositTier2(reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      const aliceShares = await vaultToken.balanceOf(alice);
      const bobShares = await vaultToken.balanceOf(bob);
      const ownerShares = await vaultToken.balanceOf(owner);

      expect(aliceShares).to.be.eq(bobShares);
      expect(aliceShares).to.be.eq(ownerShares);

      // 2x stake
      await deposit.stakeDepositTier2(reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      const aliceShares2 = await vaultToken.balanceOf(alice);
      expect(aliceShares2).to.be.eq(2n * bobShares);
    });

    it("it should be possible to redeem and withdraw stake", async function () {
      const { hyperStaking, testReserveAsset, reserveStrategy, reserveAssetPrice, vaultToken, signers } = await loadFixture(deployHyperStaking);
      const { deposit, hyperlaneHandler, realAssets, rwaUSD } = hyperStaking;
      const { alice, bob } = signers;

      expect(await vaultToken.balanceOf(alice)).to.be.eq(0);

      const stakeAmount = parseEther("3");
      await deposit.stakeDepositTier2(reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      expect(await rwaUSD.balanceOf(alice)).to.be.eq(stakeAmount); // 1:1 bridge mint

      const expectedShares = stakeAmount * parseEther("1") / reserveAssetPrice;
      expect(await vaultToken.totalAssets()).to.be.eq(stakeAmount * parseEther("1") / reserveAssetPrice);
      expect(await testReserveAsset.balanceOf(vaultToken)).to.be.gt(0);

      // redeem should be possible only through tier2 - proxy
      await expect(vaultToken.connect(alice).redeem(expectedShares, alice, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");

      // withdraw should be possible only through tier2 - proxy
      await expect(vaultToken.connect(alice).withdraw(stakeAmount, alice, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");

      // interchain redeem
      await rwaUSD.connect(alice).approve(realAssets, stakeAmount);
      const dispatchFee = await hyperlaneHandler.quoteDispatchStakeRedeem(reserveStrategy, bob, stakeAmount);
      await realAssets.connect(alice).handleRwaRedeem(
        reserveStrategy, alice, alice, stakeAmount, { value: dispatchFee },
      );

      // back to zero
      expect(await vaultToken.balanceOf(alice)).to.be.eq(0);
      expect(await rwaUSD.balanceOf(alice)).to.be.eq(0);
      expect(await testReserveAsset.balanceOf(vaultToken)).to.be.eq(0);

      // -- scenario with approval redeem
      await deposit.stakeDepositTier2(reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      // alice withdraw for bob
      await rwaUSD.connect(alice).approve(hyperlaneHandler, stakeAmount);
      await expect(realAssets.connect(alice).handleRwaRedeem(
        reserveStrategy, alice, bob, stakeAmount, { value: dispatchFee },
      )).to.changeEtherBalance(bob, stakeAmount);

      expect(await vaultToken.allowance(alice, bob)).to.be.eq(0);
      expect(await vaultToken.balanceOf(alice)).to.be.eq(0);
      expect(await vaultToken.balanceOf(bob)).to.be.eq(0);
      expect(await testReserveAsset.balanceOf(vaultToken)).to.be.eq(0);
    });

    it("fee from tier1 should increase tier2 shares value", async function () {
      const { hyperStaking, reserveStrategy, vaultToken, signers } = await loadFixture(deployHyperStaking);
      const { deposit, tier1, tier2, hyperlaneHandler, realAssets, rwaUSD } = hyperStaking;
      const { alice, bob, vaultManager, strategyManager } = signers;

      const price1 = parseEther("2");
      const price2 = parseEther("4");

      await reserveStrategy.connect(strategyManager).setAssetPrice(price1);

      const revenueFee = parseUnits("20", 16); // 20% fee
      tier1.connect(vaultManager).setRevenueFee(reserveStrategy, revenueFee);

      expect(await vaultToken.totalAssets()).to.be.eq(0);

      const aliceStakeAmount = parseEther("10");
      const bobStakeAmount = parseEther("1");

      // alice stake to tier1, bob stake to tier2
      await deposit.stakeDepositTier1(reserveStrategy, aliceStakeAmount, alice, { value: aliceStakeAmount });
      await deposit.stakeDepositTier2(reserveStrategy, bobStakeAmount, bob, { value: bobStakeAmount });

      await reserveStrategy.connect(strategyManager).setAssetPrice(price2);

      let expectedBobAllocation = bobStakeAmount * parseEther("1") / price1;
      const expectedBobShares = expectedBobAllocation;

      expect(await vaultToken.totalAssets()).to.be.eq(expectedBobAllocation);
      expect((await tier2.tier2Info(reserveStrategy)).sharesMinted).to.be.eq(expectedBobShares);

      expect(await vaultToken.totalAssets()).to.be.eq(expectedBobAllocation);

      // Tier1 withdraw generates fee
      await deposit.connect(alice).stakeWithdrawTier1(reserveStrategy, aliceStakeAmount, alice);

      const allocationFee = await tier1.allocationFee(
        reserveStrategy,
        await tier1.allocationGain(reserveStrategy, alice, aliceStakeAmount),
      );

      // shares amount does not change, but allocation should increase
      expectedBobAllocation += allocationFee;

      expect(await vaultToken.totalAssets()).to.be.eq(expectedBobAllocation);
      expect((await tier2.tier2Info(reserveStrategy)).sharesMinted).to.be.eq(expectedBobShares);

      // actual withdraw -> redeem of lpTokens
      await rwaUSD.connect(bob).approve(hyperlaneHandler, bobStakeAmount);
      const dispatchFee = await hyperlaneHandler.quoteDispatchStakeRedeem(reserveStrategy, bob, bobStakeAmount);
      await expect(realAssets.connect(bob).handleRwaRedeem(
        reserveStrategy, bob, bob, bobStakeAmount, { value: dispatchFee },
      ))
        .to.changeEtherBalance(bob, bobStakeAmount);
    });
  });
});
