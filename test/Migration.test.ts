import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { parseEther } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import * as shared from "./shared";

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testUSDC = await shared.deloyTestERC20("Test USDC", "tUSDC", 6); // 6 decimal places
  const erc4626Vault = await shared.deloyTestERC4626Vault(testUSDC);

  const testReserveAsset = await shared.deloyTestERC20("Test Reserve Asset", "tRaUSD");

  // --------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Apply Strategies --------------------

  const directUSDStrategy = await shared.createDirectStakeStrategy(
    hyperStaking.diamond, await testUSDC.getAddress(),
  );

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addDirectStrategy(
    directUSDStrategy,
    hyperStaking.rwaUSD,
  );

  // ---

  const defaultRevenueFee = parseEther("0"); // 0% fee

  const reserveAssetPrice = parseEther("2");
  const reserveUSDStrategy = await shared.createReserveStrategy(
    hyperStaking.diamond, await testUSDC.getAddress(), await testReserveAsset.getAddress(), reserveAssetPrice,
  );

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    reserveUSDStrategy,
    "reserve usd vault 1",
    "rUSD1",
    defaultRevenueFee,
    hyperStaking.rwaUSD,
  );

  // ---

  const reserveAssetPrice2 = parseEther("3");
  const reserveUSD2Strategy = await shared.createReserveStrategy(
    hyperStaking.diamond, await testUSDC.getAddress(), await testReserveAsset.getAddress(), reserveAssetPrice2,
  );

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    reserveUSD2Strategy,
    "reserve usd vault 2",
    "rUSD2",
    defaultRevenueFee,
    hyperStaking.rwaUSD,
  );

  // ---

  const ethStrategy = await shared.createZeroYieldStrategy(
    hyperStaking.diamond, shared.nativeTokenAddress,
  );

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    ethStrategy,
    "reserve eth vault 2",
    "rETH1",
    defaultRevenueFee,
    hyperStaking.rwaETH,
  );

  // ---

  // stakes with USDC, but rwaETH is generated
  const usdEthStrategy = await shared.createZeroYieldStrategy(
    hyperStaking.diamond, await testUSDC.getAddress(),
  );

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    usdEthStrategy,
    "reserve usd/eth vault 3",
    "rUETH3",
    defaultRevenueFee,
    hyperStaking.rwaETH,
  );

  // ----------------------------------------

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    testUSDC, testReserveAsset, directUSDStrategy, reserveUSDStrategy, reserveUSD2Strategy, ethStrategy, usdEthStrategy, // test contracts
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

describe("Migration", function () {
  it("strict checks should be performed before running the migration", async function () {
    const { hyperStaking, testUSDC, directUSDStrategy, reserveUSDStrategy, reserveUSD2Strategy, ethStrategy, usdEthStrategy, signers } = await loadFixture(deployHyperStaking);
    const { deposit, migration, hyperlaneHandler } = hyperStaking;
    const { migrationManager, alice, bob } = signers;

    const migrationAmount = parseEther("1000");

    // only vault manager can run the migration
    await expect(migration.migrateStrategy(directUSDStrategy, reserveUSDStrategy, migrationAmount))
      .to.be.reverted;

    await expect(migration.connect(migrationManager).migrateStrategy(directUSDStrategy, reserveUSDStrategy, 0))
      .to.be.revertedWithCustomError(migration, "ZeroAmount");

    await expect(migration.connect(migrationManager).migrateStrategy(directUSDStrategy, directUSDStrategy, migrationAmount))
      .to.be.revertedWithCustomError(migration, "SameStrategy");

    await expect(migration.connect(migrationManager).migrateStrategy(alice, directUSDStrategy, migrationAmount))
      .to.be.revertedWithCustomError(migration, "InvalidStrategy")
      .withArgs(alice);

    await expect(migration.connect(migrationManager).migrateStrategy(directUSDStrategy, bob, migrationAmount))
      .to.be.revertedWithCustomError(migration, "InvalidStrategy")
      .withArgs(bob);

    await expect(migration.connect(migrationManager).migrateStrategy(directUSDStrategy, ethStrategy, migrationAmount))
      .to.be.revertedWithCustomError(migration, "InvalidCurrency");

    await expect(migration.connect(migrationManager).migrateStrategy(reserveUSDStrategy, directUSDStrategy, migrationAmount))
      .to.be.revertedWithCustomError(migration, "DirectStrategy");

    // --- insufficient amount

    await expect(migration.connect(migrationManager).migrateStrategy(directUSDStrategy, reserveUSDStrategy, migrationAmount))
      .to.be.revertedWithCustomError(migration, "InsufficientAmount");

    await expect(migration.connect(migrationManager).migrateStrategy(reserveUSDStrategy, reserveUSD2Strategy, migrationAmount))
      .to.be.revertedWithCustomError(migration, "InsufficientAmount");

    // --- incompatible migration (different rwa token on the lumia side)

    await testUSDC.approve(deposit, migrationAmount);
    await deposit.directStakeDeposit(directUSDStrategy, migrationAmount, alice);
    await expect(migration.connect(migrationManager).migrateStrategy(directUSDStrategy, usdEthStrategy, migrationAmount))
      .to.be.revertedWithCustomError(hyperlaneHandler, "IncompatibleMigration");
  });

  it("migration from direct staking to yield generationg strategy", async function () {
    const { hyperStaking, testUSDC, directUSDStrategy, reserveUSDStrategy, signers } = await loadFixture(deployHyperStaking);
    const { deposit, lockbox, migration, realAssets, rwaUSD } = hyperStaking;
    const { migrationManager, alice } = signers;

    const stakeAmount = parseEther("20");

    await testUSDC.approve(deposit, stakeAmount);
    await deposit.directStakeDeposit(directUSDStrategy, stakeAmount, alice);

    const migrationAmount = parseEther("10");
    await expect(migration.connect(migrationManager).migrateStrategy(directUSDStrategy, reserveUSDStrategy, migrationAmount))
      .to.emit(migration, "StrategyMigrated")
      .withArgs(migrationManager, directUSDStrategy, reserveUSDStrategy, migrationAmount);

    expect(await rwaUSD.balanceOf(alice)).to.equal(stakeAmount);
    expect(await realAssets.getUserBridgedState(lockbox, rwaUSD, alice)).to.equal(stakeAmount);

    // moved value to the new strategy
    expect(await realAssets.getGeneralBridgedState(directUSDStrategy)).to.equal(stakeAmount - migrationAmount);
    expect(await realAssets.getGeneralBridgedState(reserveUSDStrategy)).to.equal(migrationAmount);

    // ---

    await rwaUSD.connect(alice).approve(realAssets, migrationAmount);
    const redeemTx = realAssets.handleRwaRedeem(reserveUSDStrategy, alice, alice, migrationAmount);

    await expect(redeemTx)
      .to.emit(realAssets, "RwaRedeem")
      .withArgs(reserveUSDStrategy, rwaUSD, alice, alice, migrationAmount);

    await expect(redeemTx)
      .to.changeTokenBalances(rwaUSD, [alice], [-migrationAmount]);

    await expect(redeemTx)
      .to.changeTokenBalances(testUSDC, [alice], [migrationAmount]);

    expect(await realAssets.getGeneralBridgedState(reserveUSDStrategy)).to.equal(0);
    expect(await realAssets.getUserBridgedState(lockbox, rwaUSD, alice)).to.equal(stakeAmount - migrationAmount);
  });

  it("migration from one yield staking strategy to another one", async function () {
    const { hyperStaking, testUSDC, reserveUSDStrategy, reserveUSD2Strategy, signers } = await loadFixture(deployHyperStaking);
    const { deposit, migration, lockbox, realAssets, rwaUSD } = hyperStaking;
    const { migrationManager, alice } = signers;

    const stakeAmount = parseEther("14");

    await testUSDC.approve(deposit, stakeAmount);
    await deposit.stakeDepositTier2(reserveUSDStrategy, stakeAmount, alice);

    const migrationAmount = parseEther("10");
    await expect(migration.connect(migrationManager).migrateStrategy(reserveUSDStrategy, reserveUSD2Strategy, migrationAmount))
      .to.emit(migration, "StrategyMigrated")
      .withArgs(migrationManager, reserveUSDStrategy, reserveUSD2Strategy, migrationAmount);

    // moved to the new strategy
    expect(await realAssets.getGeneralBridgedState(reserveUSDStrategy)).to.equal(stakeAmount - migrationAmount);
    expect(await realAssets.getGeneralBridgedState(reserveUSD2Strategy)).to.equal(migrationAmount);

    expect(await rwaUSD.balanceOf(alice)).to.equal(stakeAmount);
    expect(await realAssets.getUserBridgedState(lockbox, rwaUSD, alice)).to.equal(stakeAmount);

    // ---

    const redeemAmount = parseEther("6");
    await rwaUSD.connect(alice).approve(realAssets, redeemAmount);
    const redeemTx = realAssets.handleRwaRedeem(reserveUSD2Strategy, alice, alice, redeemAmount);

    await expect(redeemTx)
      .to.emit(realAssets, "RwaRedeem")
      .withArgs(reserveUSD2Strategy, rwaUSD, alice, alice, redeemAmount);

    await expect(redeemTx)
      .to.changeTokenBalances(rwaUSD, [alice], [-redeemAmount]);

    await expect(redeemTx)
      .to.changeTokenBalances(testUSDC, [alice], [redeemAmount]);

    expect(await realAssets.getGeneralBridgedState(reserveUSD2Strategy)).to.equal(migrationAmount - redeemAmount);
    expect(await realAssets.getUserBridgedState(lockbox, rwaUSD, alice)).to.equal(stakeAmount - redeemAmount);
  });

  it("migration from one yield staking strategy to another one with increasing vault value", async function () {
    const { hyperStaking, testUSDC, testReserveAsset, reserveUSDStrategy, reserveUSD2Strategy, signers } = await loadFixture(deployHyperStaking);
    const { deposit, tier2, lockbox, migration, realAssets, rwaUSD } = hyperStaking;
    const { migrationManager, alice } = signers;

    const stakeAmount = parseEther("18");

    await testUSDC.approve(deposit, stakeAmount);
    await deposit.stakeDepositTier2(reserveUSDStrategy, stakeAmount, alice);

    // change vault shares proportion
    const vaultToken1Address = (await tier2.tier2Info(reserveUSDStrategy)).vaultToken;
    const vaultToken1 = await ethers.getContractAt("VaultToken", vaultToken1Address);
    await testReserveAsset.mint(vaultToken1.target, parseEther("200"));

    const migrationAmount = parseEther("10");
    await expect(migration.connect(migrationManager).migrateStrategy(reserveUSDStrategy, reserveUSD2Strategy, migrationAmount))
      .to.emit(migration, "StrategyMigrated")
      .withArgs(migrationManager, reserveUSDStrategy, reserveUSD2Strategy, migrationAmount);

    // ---
    const vaultToken2Address = (await tier2.tier2Info(reserveUSD2Strategy)).vaultToken;
    const vaultToken2 = await ethers.getContractAt("VaultToken", vaultToken2Address);
    await testReserveAsset.mint(vaultToken2.target, parseEther("5000"));

    const redeemAmount = parseEther("6");
    await rwaUSD.connect(alice).approve(realAssets, redeemAmount);
    const redeemTx = realAssets.handleRwaRedeem(reserveUSD2Strategy, alice, alice, redeemAmount);

    await expect(redeemTx)
      .to.emit(realAssets, "RwaRedeem")
      .withArgs(reserveUSD2Strategy, rwaUSD, alice, alice, redeemAmount);

    await expect(redeemTx)
      .to.changeTokenBalances(rwaUSD, [alice], [-redeemAmount]);

    await expect(redeemTx)
      .to.changeTokenBalances(testUSDC, [alice], [redeemAmount]);

    expect(await realAssets.getUserBridgedState(lockbox, rwaUSD, alice)).to.equal(stakeAmount - redeemAmount);

    expect(await realAssets.getGeneralBridgedState(reserveUSD2Strategy)).to.equal(migrationAmount - redeemAmount);
  });
});
