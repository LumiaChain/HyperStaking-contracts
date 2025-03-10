import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ignition, ethers } from "hardhat";
import { expect } from "chai";
import { parseEther } from "ethers";

import TestRwaAssetModule from "../ignition/modules/test/TestRwaAsset";

import * as shared from "./shared";

async function deployHyperStaking() {
  const [owner, stakingManager, vaultManager, strategyManager, lumiaFactoryManager, bob, alice] = await ethers.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testUSDC = await shared.deloyTestERC20("Test USDC", "tUSDC", 6); // 6 decimal places
  const erc4626Vault = await shared.deloyTestERC4626Vault(testUSDC);

  // --------------------- Hyperstaking Diamond --------------------

  const { diamond, deposit, lockbox, hyperFactory, hyperlaneHandler, realAssets, rwaUSD } = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Apply Strategies --------------------

  const directStakeStrategy = await shared.createDirectStakeStrategy(
    diamond, await testUSDC.getAddress(),
  );

  await hyperFactory.connect(vaultManager).addDirectStrategy(
    directStakeStrategy,
    rwaUSD,
  );

  // ----------------------------------------

  /* eslint-disable object-property-newline */
  return {
    diamond, // diamond
    deposit, hyperFactory, lockbox, realAssets, rwaUSD, // diamond facets
    testUSDC, directStakeStrategy, hyperlaneHandler, // test contracts
    owner, stakingManager, vaultManager, strategyManager, lumiaFactoryManager, alice, bob, // addresses
  };
  /* eslint-enable object-property-newline */
}

describe("Direct Stake", function () {
  it("adding strategy should save proper data", async function () {
    const { lockbox, hyperlaneHandler, realAssets, rwaUSD, directStakeStrategy, alice, lumiaFactoryManager } = await loadFixture(deployHyperStaking);

    // check route info
    expect((await hyperlaneHandler.getRouteInfo(directStakeStrategy)).exists).to.equal(true);
    expect((await hyperlaneHandler.getRouteInfo(directStakeStrategy)).originDestination).to.equal(31337);
    expect((await hyperlaneHandler.getRouteInfo(directStakeStrategy)).originLockbox).to.equal(lockbox);
    expect((await hyperlaneHandler.getRouteInfo(directStakeStrategy)).rwaAssetOwner).to.equal(await rwaUSD.owner());
    expect((await hyperlaneHandler.getRouteInfo(directStakeStrategy)).rwaAsset).to.equal(rwaUSD);

    expect(await realAssets.getRwaAsset(directStakeStrategy)).to.equal(rwaUSD);

    // set new asset
    await expect(realAssets.connect(lumiaFactoryManager).setRwaAsset(directStakeStrategy, alice))
      // custom error from LibInterchainFactory (unfortunetaly hardhat doesn't support it)
      .to.be.reverted;

    const { rwaAsset, rwaAssetOwner } = await ignition.deploy(TestRwaAssetModule);
    await expect(realAssets.connect(lumiaFactoryManager).setRwaAsset(directStakeStrategy, rwaAsset))
      // minter not set
      // custom error from LibInterchainFactory (unfortunetaly hardhat doesn't support it)
      .to.be.reverted;

    // ok
    await rwaAssetOwner.addMinter(realAssets);
    await realAssets.connect(lumiaFactoryManager).setRwaAsset(directStakeStrategy, rwaAsset);

    expect(await realAssets.getRwaAsset(directStakeStrategy)).to.equal(rwaAsset);
    expect((await hyperlaneHandler.getRouteInfo(directStakeStrategy)).rwaAssetOwner).to.equal(rwaAssetOwner);
    expect((await hyperlaneHandler.getRouteInfo(directStakeStrategy)).rwaAsset).to.equal(rwaAsset);
  });

  it("only direct stake strategy should be allowed for direct staking", async function () {
    const { diamond, deposit, hyperFactory, realAssets, testUSDC, rwaUSD, directStakeStrategy, alice, vaultManager } = await loadFixture(deployHyperStaking);

    // adding new non-direct stake strategy
    const reserveAssetPrice = parseEther("2");
    const reserveStrategy = await shared.createReserveStrategy(
      diamond, shared.nativeTokenAddress, await testUSDC.getAddress(), reserveAssetPrice,
    );

    await hyperFactory.connect(vaultManager).addStrategy(
      reserveStrategy,
      "eth reserve vault1",
      "rUSD",
      parseEther("0"),
      rwaUSD,
    );

    const stakeAmount = parseEther("1000");
    await expect(deposit.directStakeDeposit(reserveStrategy, stakeAmount, alice))
      .to.be.revertedWithCustomError(deposit, "NotDirectDeposit")
      .withArgs(reserveStrategy.target);

    await testUSDC.approve(deposit, stakeAmount);
    await expect(deposit.directStakeDeposit(directStakeStrategy, stakeAmount, alice))
      .to.emit(realAssets, "RwaMint")
      .withArgs(directStakeStrategy.target, rwaUSD, alice, stakeAmount);
  });

  it("direct stake strategy should mint rwaUSD in 1:1 ratio", async function () {
    const { deposit, testUSDC, realAssets, rwaUSD, directStakeStrategy, alice } = await loadFixture(deployHyperStaking);

    const stakeAmount = parseEther("500");

    await testUSDC.approve(deposit, stakeAmount);
    await deposit.directStakeDeposit(directStakeStrategy, stakeAmount, alice);

    expect((await deposit.directStakeInfo(directStakeStrategy)).totalStake).to.equal(stakeAmount);

    expect(await rwaUSD.balanceOf(alice)).to.equal(stakeAmount);
    expect(await realAssets.getUserBridgedState(directStakeStrategy, alice)).to.equal(stakeAmount);
  });

  it("rwaUSD could be redeemend back to origin chain in the same 1:1 ratio", async function () {
    const { deposit, testUSDC, realAssets, rwaUSD, directStakeStrategy, alice, bob } = await loadFixture(deployHyperStaking);

    const stakeAmount = parseEther("500");

    await testUSDC.approve(deposit, stakeAmount);
    await deposit.directStakeDeposit(directStakeStrategy, stakeAmount, alice);

    await rwaUSD.connect(alice).approve(realAssets, stakeAmount);
    await expect(realAssets.handleRwaRedeem(directStakeStrategy, alice, bob, stakeAmount))
      .to.emit(realAssets, "RwaRedeem")
      .withArgs(directStakeStrategy.target, rwaUSD, alice, bob, stakeAmount);

    expect((await deposit.directStakeInfo(directStakeStrategy)).totalStake).to.equal(0);

    expect(await rwaUSD.balanceOf(alice)).to.equal(0);
    expect(await realAssets.getUserBridgedState(directStakeStrategy, alice)).to.equal(0);
  });

  it("it should be possible to use rwa asset like erc20, but only the initial staker can bridge out", async function () {
    const { deposit, testUSDC, directStakeStrategy, realAssets, rwaUSD, owner, alice, bob } = await loadFixture(deployHyperStaking);

    const stakeAmount = parseEther("3");

    await testUSDC.approve(deposit, stakeAmount);
    await deposit.directStakeDeposit(directStakeStrategy, stakeAmount, alice);
    const initBalance = await rwaUSD.balanceOf(alice);

    await rwaUSD.connect(alice).approve(bob, initBalance);
    await rwaUSD.connect(bob).transferFrom(alice, bob, initBalance);

    expect(await rwaUSD.balanceOf(alice)).to.be.eq(0);
    expect(await rwaUSD.balanceOf(bob)).to.be.eq(initBalance);
    expect(await rwaUSD.balanceOf(owner)).to.be.eq(0);

    await rwaUSD.connect(bob).transfer(owner, initBalance);

    expect(await rwaUSD.balanceOf(alice)).to.be.eq(0);
    expect(await rwaUSD.balanceOf(bob)).to.be.eq(0);
    expect(await rwaUSD.balanceOf(owner)).to.be.eq(initBalance);

    // TODO: test that only the initial staker can bridge out
    await rwaUSD.approve(realAssets, initBalance);
    await expect(realAssets.handleRwaRedeem(directStakeStrategy, owner, owner, stakeAmount))
      .to.be.revertedWithCustomError(realAssets, "InsufficientBridgedState");

    await rwaUSD.transfer(alice, initBalance);

    // OK
    await rwaUSD.connect(alice).approve(realAssets, initBalance);
    await realAssets.handleRwaRedeem(directStakeStrategy, alice, alice, stakeAmount);
  });
});
