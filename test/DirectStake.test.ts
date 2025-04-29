import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { parseEther } from "ethers";

import * as shared from "./shared";

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testUSDC = await shared.deloyTestERC20("Test USDC", "tUSDC", 6); // 6 decimal places
  const erc4626Vault = await shared.deloyTestERC4626Vault(testUSDC);

  // --------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Apply Strategies --------------------

  const directStakeStrategy = await shared.createDirectStakeStrategy(
    hyperStaking.diamond, await testUSDC.getAddress(),
  );

  const vaultTokenName = "Direct USD";
  const vaultTokenSymbol = "dUSD";
  await hyperStaking.hyperFactory.connect(signers.vaultManager).addDirectStrategy(
    directStakeStrategy,
    vaultTokenName,
    vaultTokenSymbol,
  );

  const lumiaAssetTokenAddress = (await hyperStaking.hyperlaneHandler.getRouteInfo(directStakeStrategy)).assetToken;
  const lumiaAssetToken = await ethers.getContractAt("TestERC20", lumiaAssetTokenAddress);

  // ----------------------------------------

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    testUSDC, directStakeStrategy, lumiaAssetToken, // test contracts
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

describe("Direct Stake", function () {
  it("adding strategy should save proper data", async function () {
    const { hyperStaking, directStakeStrategy, lumiaAssetToken } = await loadFixture(deployHyperStaking);
    const { lockbox, hyperlaneHandler } = hyperStaking;

    // check route info
    expect((await hyperlaneHandler.getRouteInfo(directStakeStrategy)).exists).to.equal(true);
    expect((await hyperlaneHandler.getRouteInfo(directStakeStrategy)).originDestination).to.equal(31337);
    expect((await hyperlaneHandler.getRouteInfo(directStakeStrategy)).originLockbox).to.equal(lockbox);
    expect((await hyperlaneHandler.getRouteInfo(directStakeStrategy)).assetToken).to.equal(lumiaAssetToken);
  });

  it("only direct stake strategy should be allowed for direct staking", async function () {
    const { hyperStaking, testUSDC, directStakeStrategy, signers } = await loadFixture(deployHyperStaking);
    const { diamond, deposit, hyperFactory, realAssets } = hyperStaking;
    const { alice, vaultManager } = signers;

    // adding new non-direct stake strategy
    const reserveAssetPrice = parseEther("2");
    const reserveStrategy = await shared.createReserveStrategy(
      diamond, shared.nativeTokenAddress, await testUSDC.getAddress(), reserveAssetPrice,
    );

    await hyperFactory.connect(vaultManager).addStrategy(
      reserveStrategy,
      "eth reserve vault1",
      "rUSD",
    );

    const stakeAmount = parseEther("1000");
    await expect(deposit.directStakeDeposit(reserveStrategy, stakeAmount, alice))
      .to.be.revertedWithCustomError(deposit, "NotDirectDeposit")
      .withArgs(reserveStrategy.target);

    await testUSDC.approve(deposit, stakeAmount);
    await expect(deposit.directStakeDeposit(directStakeStrategy, stakeAmount, alice))
      .to.emit(realAssets, "RwaMint")
      .withArgs(directStakeStrategy.target, alice, stakeAmount);
  });

  it("direct stake strategy should mint lumia asset in 1:1 ratio", async function () {
    const { hyperStaking, testUSDC, directStakeStrategy, lumiaAssetToken, signers } = await loadFixture(deployHyperStaking);
    const { deposit, realAssets } = hyperStaking;
    const { alice } = signers;

    const stakeAmount = parseEther("500");

    await testUSDC.approve(deposit, stakeAmount);
    await deposit.directStakeDeposit(directStakeStrategy, stakeAmount, alice);

    expect((await deposit.directStakeInfo(directStakeStrategy)).totalStake).to.equal(stakeAmount);

    expect(await lumiaAssetToken.balanceOf(alice)).to.equal(stakeAmount);
    expect(await realAssets.getGeneralBridgedState(directStakeStrategy)).to.equal(stakeAmount);
  });

  // TODO: lumia shared redeem
  // it("lumia rwa shares could be redeemend back to origin chain in the same 1:1 ratio", async function () {
  //   const { hyperStaking, testUSDC, directStakeStrategy, signers } = await loadFixture(deployHyperStaking);
  //   const { deposit, realAssets, lockbox, rwaUSD } = hyperStaking;
  //   const { alice, bob } = signers;
  //
  //   const stakeAmount = parseEther("500");
  //
  //   await testUSDC.approve(deposit, stakeAmount);
  //   await deposit.directStakeDeposit(directStakeStrategy, stakeAmount, alice);
  //
  //   await rwaUSD.connect(alice).approve(realAssets, stakeAmount);
  //   await expect(realAssets.handleRwaRedeem(directStakeStrategy, alice, bob, stakeAmount))
  //     .to.emit(realAssets, "RwaRedeem")
  //     .withArgs(directStakeStrategy.target, rwaUSD, alice, bob, stakeAmount);
  //
  //   expect((await deposit.directStakeInfo(directStakeStrategy)).totalStake).to.equal(0);
  //
  //   expect(await rwaUSD.balanceOf(alice)).to.equal(0);
  //   expect(await realAssets.getUserBridgedState(lockbox, rwaUSD, alice)).to.equal(0);
  //   expect(await realAssets.getGeneralBridgedState(directStakeStrategy)).to.equal(0);
  // });

  // TODO: lumia shared redeem 2
  // it("rwa shares should behave like ERC-20s and be redeemable by other users", async function () {
  //   const { hyperStaking, testUSDC, directStakeStrategy, signers } = await loadFixture(deployHyperStaking);
  //   const { deposit, realAssets, rwaUSD } = hyperStaking;
  //   const { owner, alice, bob } = signers;
  //
  //   const stakeAmount = parseEther("3");
  //
  //   await testUSDC.approve(deposit, stakeAmount);
  //   await deposit.directStakeDeposit(directStakeStrategy, stakeAmount, alice);
  //   const initBalance = await rwaUSD.balanceOf(alice);
  //
  //   await rwaUSD.connect(alice).approve(bob, initBalance);
  //   await rwaUSD.connect(bob).transferFrom(alice, bob, initBalance);
  //
  //   expect(await rwaUSD.balanceOf(alice)).to.be.eq(0);
  //   expect(await rwaUSD.balanceOf(bob)).to.be.eq(initBalance);
  //   expect(await rwaUSD.balanceOf(owner)).to.be.eq(0);
  //
  //   await rwaUSD.connect(bob).transfer(owner, initBalance);
  //
  //   expect(await rwaUSD.balanceOf(alice)).to.be.eq(0);
  //   expect(await rwaUSD.balanceOf(bob)).to.be.eq(0);
  //   expect(await rwaUSD.balanceOf(owner)).to.be.eq(initBalance);
  //
  //   await rwaUSD.approve(realAssets, initBalance);
  //   await expect(realAssets.handleRwaRedeem(directStakeStrategy, owner, owner, stakeAmount))
  //     .to.be.revertedWithCustomError(realAssets, "InsufficientUserState");
  //
  //   await rwaUSD.transfer(alice, initBalance);
  //
  //   // OK
  //   await rwaUSD.connect(alice).approve(realAssets, initBalance);
  //   await realAssets.handleRwaRedeem(directStakeStrategy, alice, alice, stakeAmount);
  // });
});
