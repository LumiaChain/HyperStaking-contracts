import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { parseEther, ZeroAddress } from "ethers";

import * as shared from "./shared";

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testReserveAsset = await shared.deloyTestERC20("Test Reserve Asset", "tRaETH");
  const erc4626Vault = await shared.deloyTestERC4626Vault(testReserveAsset);

  // -------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Apply Strategies --------------------

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
  );

  const vaultTokenAddress = (await hyperStaking.stakeVault.stakeInfo(reserveStrategy)).vaultToken;
  const vaultToken = await ethers.getContractAt("VaultToken", vaultTokenAddress);

  const lumiaAssetTokenAddress = (await hyperStaking.hyperlaneHandler.getRouteInfo(reserveStrategy)).assetToken;
  const lumiaAssetToken = await ethers.getContractAt("TestERC20", lumiaAssetTokenAddress);

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    testReserveAsset, reserveStrategy, vaultToken, // test contracts
    reserveAssetPrice, vaultTokenName, vaultTokenSymbol, // values
    lumiaAssetToken, signers, // signers
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

  describe("StakeVault", function () {
    it("it shouldn't be possible to mint shares apart from the diamond", async function () {
      const { vaultToken, signers } = await loadFixture(deployHyperStaking);
      const { alice } = signers;

      await expect(vaultToken.deposit(100, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");

      await expect(vaultToken.mint(100, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");
    });

    it("it should be possible to stake deposit to vault", async function () {
      const { hyperStaking, reserveStrategy, vaultToken, signers } = await loadFixture(deployHyperStaking);
      const { deposit } = hyperStaking;
      const { owner, alice } = signers;

      const stakeAmount = parseEther("6");

      const depositType = 1;
      await expect(deposit.stakeDeposit(
        reserveStrategy, stakeAmount, alice, { value: stakeAmount },
      ))
        .to.emit(deposit, "StakeDeposit")
        .withArgs(owner, alice, reserveStrategy, stakeAmount, depositType);

      // shares calculations
      const allocation = await reserveStrategy.previewAllocation(stakeAmount);
      const expectedShares = await vaultToken.previewDeposit(allocation);

      expect(await vaultToken.totalSupply()).to.be.eq(expectedShares);
    });

    it("shares should be minted equally regardless of the deposit order", async function () {
      const { hyperStaking, reserveStrategy, vaultToken, signers } = await loadFixture(deployHyperStaking);
      const { deposit } = hyperStaking;
      const { owner, alice, bob } = signers;

      const stakeAmount = parseEther("7");

      await deposit.stakeDeposit(reserveStrategy, stakeAmount, owner, { value: stakeAmount });
      await deposit.stakeDeposit(reserveStrategy, stakeAmount, bob, { value: stakeAmount });
      await deposit.stakeDeposit(reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      const aliceShares = await vaultToken.balanceOf(alice);
      const bobShares = await vaultToken.balanceOf(bob);
      const ownerShares = await vaultToken.balanceOf(owner);

      expect(aliceShares).to.be.eq(bobShares);
      expect(aliceShares).to.be.eq(ownerShares);

      // 2x stake
      await deposit.stakeDeposit(reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      const aliceShares2 = await vaultToken.balanceOf(alice);
      expect(aliceShares2).to.be.eq(2n * bobShares);
    });

    it("it should be possible to redeem and withdraw stake", async function () {
      const {
        hyperStaking, testReserveAsset, reserveStrategy, reserveAssetPrice, vaultToken, lumiaAssetToken, signers,
      } = await loadFixture(deployHyperStaking);
      const { deposit } = hyperStaking;
      const {
        alice,
        // bob
      } = signers;

      expect(await vaultToken.balanceOf(alice)).to.be.eq(0);

      const stakeAmount = parseEther("3");
      await deposit.stakeDeposit(reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      expect(await lumiaAssetToken.balanceOf(alice)).to.be.eq(stakeAmount); // 1:1 bridge mint

      const expectedShares = stakeAmount * parseEther("1") / reserveAssetPrice;
      expect(await vaultToken.totalAssets()).to.be.eq(stakeAmount * parseEther("1") / reserveAssetPrice);
      expect(await testReserveAsset.balanceOf(vaultToken)).to.be.gt(0);

      // redeem should be possible only through tier2 - proxy
      await expect(vaultToken.connect(alice).redeem(expectedShares, alice, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");

      // withdraw should be possible only through tier2 - proxy
      await expect(vaultToken.connect(alice).withdraw(stakeAmount, alice, alice))
        .to.be.revertedWithCustomError(vaultToken, "OwnableUnauthorizedAccount");

      // interchain redeem TODO: vault shares redeem
      /*
      await rwaUSD.connect(alice).approve(realAssets, stakeAmount);
      const dispatchFee = await hyperlaneHandler.quoteDispatchStakeRedeem(reserveStrategy, bob, stakeAmount);
      await realAssets.connect(alice).handleRwaRedeem(
        reserveStrategy, alice, alice, stakeAmount, { value: dispatchFee },
      );

      // back to zero
      expect(await vaultToken.balanceOf(alice)).to.be.eq(0);
      expect(await lumiaAssetToken.balanceOf(alice)).to.be.eq(0);
      expect(await testReserveAsset.balanceOf(vaultToken)).to.be.eq(0);

      // -- scenario with approval redeem
      await deposit.stakeDeposit(reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      // alice withdraw for bob
      await rwaUSD.connect(alice).approve(hyperlaneHandler, stakeAmount);
      await expect(realAssets.connect(alice).handleRwaRedeem(
        reserveStrategy, alice, bob, stakeAmount, { value: dispatchFee },
      )).to.changeEtherBalance(bob, stakeAmount);

      expect(await vaultToken.allowance(alice, bob)).to.be.eq(0);
      expect(await vaultToken.balanceOf(alice)).to.be.eq(0);
      expect(await vaultToken.balanceOf(bob)).to.be.eq(0);
      expect(await testReserveAsset.balanceOf(vaultToken)).to.be.eq(0);
      */
    });
  });
});
