import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { parseEther, ZeroAddress } from "ethers";

import * as shared from "./shared";

import { StakeRedeemDataStruct } from "../typechain-types/contracts/lumia-diamond/interfaces/IStakeRedeemRoute";

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testReserveAsset = await shared.deloyTestERC20("Test Reserve Asset", "tRaETH");

  // -------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n);

  // -------------------- Apply Strategies --------------------

  // strategy asset price to eth 2:1
  const reserveAssetPrice = parseEther("2");

  const reserveStrategy = await shared.createReserveStrategy(
    hyperStaking.diamond, shared.nativeTokenAddress, await testReserveAsset.getAddress(), reserveAssetPrice,
  );

  const vaultSharesName = "eth vault1";
  const vaultSharesSymbol = "vETH1";

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    reserveStrategy,
    vaultSharesName,
    vaultSharesSymbol,
  );

  // -------------------- Hyperlane Handler --------------------

  const { principalToken, vaultShares } = await shared.getDerivedTokens(
    hyperStaking.hyperlaneHandler,
    await reserveStrategy.getAddress(),
  );

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    testReserveAsset, reserveStrategy, principalToken, vaultShares, // test contracts
    reserveAssetPrice, vaultSharesName, vaultSharesSymbol, // values
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

describe("VaultShares", function () {
  describe("InterchainFactory", function () {
    it("vault token name, symbol and decimals", async function () {
      const { testReserveAsset, principalToken, vaultShares, vaultSharesName, vaultSharesSymbol } = await loadFixture(deployHyperStaking);

      expect(await principalToken.name()).to.equal(`Principal ${vaultSharesName}`);
      expect(await principalToken.symbol()).to.equal("p" + vaultSharesSymbol);

      expect(await vaultShares.name()).to.equal(vaultSharesName);
      expect(await vaultShares.symbol()).to.equal(vaultSharesSymbol);

      const testReserveAssetDecimals = await testReserveAsset.decimals();

      expect(testReserveAssetDecimals).to.equal(18);
      expect(testReserveAssetDecimals).to.equal(await principalToken.decimals());
      expect(testReserveAssetDecimals).to.equal(await vaultShares.decimals());
    });

    it("test route and registration", async function () {
      const { hyperStaking, reserveStrategy, signers } = await loadFixture(deployHyperStaking);
      const { diamond, hyperFactory, hyperlaneHandler } = hyperStaking;
      const { vaultManager } = signers;

      const testAsset2 = await shared.deloyTestERC20("Test Asset2", "tRaETH2");
      const testAsset3 = await shared.deloyTestERC20("Test Asset3", "tRaETH3");

      const reserveStrategy2 = await shared.createReserveStrategy(
        diamond, shared.nativeTokenAddress, await testAsset2.getAddress(), parseEther("2"),
      );
      const reserveStrategy3 = await shared.createReserveStrategy(
        diamond, shared.nativeTokenAddress, await testAsset3.getAddress(), parseEther("3"),
      );

      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy2)).exists).to.equal(false);
      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy3)).exists).to.equal(false);

      // by adding new stategies more vault tokens should be created
      await hyperFactory.connect(vaultManager).addStrategy(
        reserveStrategy2,
        "eth vault2",
        "vETH2",
      );

      await hyperFactory.connect(vaultManager).addStrategy(
        reserveStrategy3,
        "eth vault3",
        "vETH3",
      );

      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy)).exists).to.equal(true);
      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy)).assetToken).to.not.equal(ZeroAddress);

      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy2)).exists).to.equal(true);
      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy2)).assetToken).to.not.equal(ZeroAddress);

      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy3)).exists).to.equal(true);
      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy3)).assetToken).to.not.equal(ZeroAddress);
    });
  });

  describe("Allocation", function () {
    it("it shouldn't be possible to mint shares apart from the diamond", async function () {
      const { principalToken, vaultShares, signers } = await loadFixture(deployHyperStaking);
      const { alice } = signers;

      await expect(principalToken.mint(alice, 100))
        .to.be.revertedWithCustomError(vaultShares, "OwnableUnauthorizedAccount");

      await expect(vaultShares.deposit(100, alice))
        .to.be.revertedWithCustomError(vaultShares, "OwnableUnauthorizedAccount");

      await expect(vaultShares.mint(100, alice))
        .to.be.revertedWithCustomError(vaultShares, "OwnableUnauthorizedAccount");
    });

    it("stake deposit should generate vault shares", async function () {
      const { hyperStaking, reserveStrategy, principalToken, vaultShares, signers } = await loadFixture(deployHyperStaking);
      const { deposit, allocation } = hyperStaking;
      const { owner, vaultManager, strategyManager, alice } = signers;

      const stakeAmount = parseEther("6");

      const depositType = 1;
      await expect(deposit.stakeDeposit(
        reserveStrategy, alice, stakeAmount, { value: stakeAmount },
      ))
        .to.emit(deposit, "StakeDeposit")
        .withArgs(owner, alice, reserveStrategy, stakeAmount, depositType);

      // both principalToken and shares should be minted in ration 1:1 to the stake at start
      expect(await vaultShares.totalSupply()).to.be.eq(stakeAmount);
      expect(await principalToken.totalSupply()).to.be.eq(stakeAmount);

      // simulate yield generation, increase asset price
      const assetPrice = await reserveStrategy.assetPrice();
      await reserveStrategy.connect(strategyManager).setAssetPrice(assetPrice * 2n);

      // compound stake
      const feeRecipient = vaultManager;
      await allocation.connect(vaultManager).setFeeRecipient(reserveStrategy, feeRecipient);
      await allocation.connect(vaultManager).report(reserveStrategy);

      // amount of shares stays the same
      expect(await vaultShares.totalSupply()).to.be.eq(stakeAmount);

      // principalToken amount should be increased
      const totalStake = (await allocation.stakeInfo(reserveStrategy)).totalStake;
      expect(await vaultShares.totalAssets()).to.be.eq(totalStake);
    });

    it("shares should be minted equally regardless of the deposit order", async function () {
      const { hyperStaking, reserveStrategy, vaultShares, signers } = await loadFixture(deployHyperStaking);
      const { deposit } = hyperStaking;
      const { owner, alice, bob } = signers;

      const stakeAmount = parseEther("7");

      await deposit.stakeDeposit(reserveStrategy, owner, stakeAmount, { value: stakeAmount });
      await deposit.stakeDeposit(reserveStrategy, bob, stakeAmount, { value: stakeAmount });
      await deposit.stakeDeposit(reserveStrategy, alice, stakeAmount, { value: stakeAmount });

      const aliceShares = await vaultShares.balanceOf(alice);
      const bobShares = await vaultShares.balanceOf(bob);
      const ownerShares = await vaultShares.balanceOf(owner);

      expect(aliceShares).to.be.eq(bobShares);
      expect(aliceShares).to.be.eq(ownerShares);

      // 2x stake
      await deposit.stakeDeposit(reserveStrategy, alice, stakeAmount, { value: stakeAmount });

      const aliceShares2 = await vaultShares.balanceOf(alice);
      expect(aliceShares2).to.be.eq(2n * bobShares);
    });

    it("it should be possible to redeem and withdraw stake", async function () {
      const {
        hyperStaking, testReserveAsset, reserveStrategy, reserveAssetPrice, principalToken, vaultShares, signers,
      } = await loadFixture(deployHyperStaking);
      const { deposit, defaultWithdrawDelay, lockbox, realAssets, stakeRedeemRoute } = hyperStaking;
      const {
        alice,
        bob,
      } = signers;

      expect(await vaultShares.balanceOf(alice)).to.be.eq(0);

      const stakeAmount = parseEther("3");
      await deposit.stakeDeposit(reserveStrategy, alice, stakeAmount, { value: stakeAmount });

      expect(await principalToken.totalSupply()).to.be.eq(stakeAmount); // 1:1 bridge mint
      expect(await principalToken.balanceOf(vaultShares)).to.be.eq(stakeAmount); // locked in vault

      expect(await vaultShares.totalAssets()).to.be.eq(stakeAmount);

      // check allocation
      const expectedAllocation = stakeAmount * parseEther("1") / reserveAssetPrice;
      expect(await testReserveAsset.balanceOf(lockbox)).to.be.eq(expectedAllocation);

      // redeem should be possible only through realAssets facet - lumia proxy
      await expect(vaultShares.connect(alice).redeem(stakeAmount, alice, alice))
        .to.be.revertedWithCustomError(vaultShares, "OwnableUnauthorizedAccount");

      // withdraw should be possible only through realAssets facet - lumia proxy
      await expect(vaultShares.connect(alice).withdraw(stakeAmount, alice, alice))
        .to.be.revertedWithCustomError(vaultShares, "OwnableUnauthorizedAccount");

      // interchain redeem
      await vaultShares.connect(alice).approve(realAssets, stakeAmount);

      const stakeRedeemData: StakeRedeemDataStruct = {
        strategy: reserveStrategy,
        sender: alice,
        redeemAmount: stakeAmount,
      };
      const dispatchFee = await stakeRedeemRoute.quoteDispatchStakeRedeem(stakeRedeemData);

      await vaultShares.connect(alice).approve(realAssets, stakeAmount);
      await realAssets.connect(alice).redeem(
        reserveStrategy, alice, alice, stakeAmount, { value: dispatchFee },
      );

      // back to zero
      expect(await vaultShares.balanceOf(alice)).to.be.eq(0);
      expect(await principalToken.balanceOf(vaultShares)).to.be.eq(0);
      expect(await testReserveAsset.balanceOf(lockbox)).to.be.eq(0);

      // -- scenario with approval redeem
      await deposit.stakeDeposit(reserveStrategy, alice, stakeAmount, { value: stakeAmount });

      // alice withdraw for bob
      await vaultShares.connect(alice).approve(realAssets, stakeAmount);
      const expectedUnlock = await shared.getCurrentBlockTimestamp() + defaultWithdrawDelay;
      await expect(realAssets.connect(alice).redeem(
        reserveStrategy, alice, bob, stakeAmount, { value: dispatchFee },
      )).to.changeEtherBalance(lockbox, stakeAmount);

      expect(await vaultShares.allowance(alice, bob)).to.be.eq(0);
      expect(await vaultShares.balanceOf(alice)).to.be.eq(0);
      expect(await vaultShares.balanceOf(bob)).to.be.eq(0);

      await time.setNextBlockTimestamp(expectedUnlock);
      await expect(deposit.connect(bob).claimWithdraw(reserveStrategy, bob))
        .to.changeEtherBalance(bob, stakeAmount);

      expect(await testReserveAsset.balanceOf(lockbox)).to.be.eq(0);
    });
  });
});
