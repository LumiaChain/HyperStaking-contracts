import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers, ignition } from "hardhat";
import { parseEther, parseUnits, Contract, ZeroAddress } from "ethers";

import ThreeADaoMockModule from "../ignition/modules/test/3adaoMock";

import * as shared from "./shared";

describe("3adao-lumia", function () {
  async function getMocked3adao() {
    const [owner, alice] = await ethers.getSigners();
    const { rwaUSD, threeAVaultFactory, tokenToPriceFeed } = await ignition.deploy(ThreeADaoMockModule);

    await threeAVaultFactory.createVault("test vault");
    const testVaultAddress = await threeAVaultFactory.vaultsByOwner(owner.address, 0);
    const testVault = await ethers.getContractAt("SmartVault", testVaultAddress);

    return { rwaUSD, threeAVaultFactory, tokenToPriceFeed, testVault, owner, alice };
  };

  async function deployHyperStaking() {
    const [owner, stakingManager, vaultManager, strategyManager, lumiaFactoryManager, bob, alice] = await ethers.getSigners();

    // -------------------- Deploy Tokens --------------------

    const testUSDC = await shared.deloyTestERC20("Test USD Coin", "tUSDC", 6);
    const erc4626Vault = await shared.deloyTestERC4626Vault(testUSDC);

    await testUSDC.mint(alice.address, parseUnits("1000000", 6));

    // -------------------- Hyperstaking Diamond --------------------

    const {
      mailbox, hyperlaneHandler, routeFactory, diamond, deposit, hyperFactory, tier1, tier2, lockbox, rwaUSD, threeAVaultFactory, tokenToPriceFeed,
    } = await shared.deployTestHyperStaking(0n, erc4626Vault);

    // -------------------- Apply Strategies --------------------

    const defaultRevenueFee = parseEther("0"); // 0% fee

    const zeroYieldStrategy = await shared.createZeroYieldStrategy(
      diamond,
      await testUSDC.getAddress(),
    );

    await hyperFactory.connect(vaultManager).addStrategy(
      zeroYieldStrategy,
      "zero yield USDC",
      "zUSDC",
      defaultRevenueFee,
    );

    const { vaultToken, lpToken } = await shared.getDerivedTokens(
      tier2, routeFactory, await zeroYieldStrategy.getAddress(),
    );

    // -------------------- Lending Configuration --------------------

    const lendingVaultAddress = await routeFactory.getLendingVault(zeroYieldStrategy);
    const lendingVault = await ethers.getContractAt("SmartVault", lendingVaultAddress);

    const usdcCollateralCapacity = parseUnits("10000", 6);
    await threeAVaultFactory.setCollateralCapacity(lpToken, usdcCollateralCapacity);

    const tokenPrice = parseUnits("1", 6);
    await shared.addTestPriceFeed(
      tokenToPriceFeed,
      lpToken as unknown as Contract,
      tokenPrice,
    );

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      deposit, hyperFactory, tier1, tier2, lockbox, // diamond facets
      mailbox, hyperlaneHandler, routeFactory, testUSDC, zeroYieldStrategy, vaultToken, lpToken,
      lendingVault, rwaUSD, // test contracts
      defaultRevenueFee, usdcCollateralCapacity, // values
      owner, stakingManager, vaultManager, strategyManager, lumiaFactoryManager, alice, bob, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("RouteFactory", function () {
    it("route factory use lending integration and sent rwaUSD to the user", async function () {
      const { deposit, zeroYieldStrategy, testUSDC, alice, vaultToken, lockbox, lpToken, hyperlaneHandler, rwaUSD, lendingVault } = await deployHyperStaking();

      const stakeAmount = parseUnits("400", 6);

      await testUSDC.connect(alice).approve(deposit, stakeAmount);
      const stakeTx = deposit.connect(alice).stakeDepositTier2(
        zeroYieldStrategy, stakeAmount, alice,
      );

      // --- examine move of value

      // initial stake goes to erc4626 strategy-vault
      await expect(stakeTx).to.changeTokenBalances(
        testUSDC,
        [alice, vaultToken], [-stakeAmount, stakeAmount],
      );

      // strategy-vault shares are locked in lockbox
      await expect(stakeTx).to.changeTokenBalance(vaultToken, lockbox, stakeAmount);

      // lpTokens are minted on the lumia side and goes to lending vault as collateral
      await expect(stakeTx).to.changeTokenBalance(lpToken, lendingVault, stakeAmount);

      // rwaUSD is borrowed and sent to the user (minus borrow safety buffer)
      const borrowSafetyBuffer = (await hyperlaneHandler.getRouteInfo(zeroYieldStrategy)).borrowSafetyBuffer;
      expect(borrowSafetyBuffer).to.be.equal(parseEther("0.05")); // 5%
      const expecteRwaUSDAmount = stakeAmount * (parseEther("1") - borrowSafetyBuffer) / parseEther("1");

      // check vault health
      await expect(stakeTx).to.changeTokenBalance(rwaUSD, alice, expecteRwaUSDAmount);

      const [borrowable, maxBorrowable] = await lendingVault.borrowable();
      expect(borrowable).to.be.equal(stakeAmount);
      expect(maxBorrowable).to.be.equal(stakeAmount / 20n);
      expect(await lendingVault.healthFactor(true)).to.be.gt(parseEther("1.05"));
    });

    it("it should be possible to redeem rwaUSD back to lpToken and origin chain", async function () {
      const {
        deposit, zeroYieldStrategy, testUSDC, alice, vaultToken, lockbox, lpToken, routeFactory, rwaUSD, lendingVault, lumiaFactoryManager,
      } = await deployHyperStaking();

      const stakeAmount = parseUnits("1000", 6);

      // change safety buffer to 1%
      await expect(routeFactory.connect(lumiaFactoryManager).updateLendingProperties(zeroYieldStrategy, true, parseEther("0.01")))
        .to.emit(routeFactory, "LendingPropertiesUpdated")
        .withArgs(zeroYieldStrategy, true, parseEther("0.01"));

      await testUSDC.connect(alice).approve(deposit, stakeAmount);
      await deposit.connect(alice).stakeDepositTier2(
        zeroYieldStrategy, stakeAmount, alice,
      );

      const rwaUSDAmount = parseUnits("990", 6);
      expect(await rwaUSD.balanceOf(alice)).to.be.equal(rwaUSDAmount); // check expected value

      const precisionError = 1n;
      const redemptionRate = parseUnits("0.005", 6);
      const sharesRedeemAmount = rwaUSDAmount * parseUnits("1", 6) / (parseUnits("1", 6) + redemptionRate) + precisionError;

      await rwaUSD.connect(alice).approve(routeFactory, rwaUSDAmount);
      const redeemTx = routeFactory.connect(alice).redeemRwaTokens(
        zeroYieldStrategy, alice, sharesRedeemAmount,
      );

      // --- examine move of value

      // rwaUSD is used to payback debt
      await expect(redeemTx).to.changeTokenBalance(rwaUSD, alice, -rwaUSDAmount);
      expect(await rwaUSD.totalSupply()).to.lt(parseUnits("5", 6));

      // lpTokens are released from the lending vault and are burned on the lumia side
      await expect(redeemTx).to.changeTokenBalance(lpToken, lendingVault, -sharesRedeemAmount);
      expect(await lpToken.totalSupply()).to.lt(parseUnits("15", 6));

      // strategy-vault shares are unlocked from lockbox
      await expect(redeemTx).to.changeTokenBalance(vaultToken, lockbox, -sharesRedeemAmount);

      // initial stake goes back to the user
      await expect(redeemTx).to.changeTokenBalances(
        testUSDC,
        [alice, vaultToken], [sharesRedeemAmount, -sharesRedeemAmount],
      );

      const [borrowable] = await lendingVault.borrowable();
      expect(borrowable).to.be.gt(parseUnits("10", 6));
      expect(await lendingVault.healthFactor(true)).to.be.gt(parseEther("3.00"));
    });
  });

  describe("Mock", function () {
    it("it should be possible to create new vault", async function () {
      const { rwaUSD, threeAVaultFactory, alice } = await loadFixture(getMocked3adao);

      await threeAVaultFactory.connect(alice).createVault("test vault2");
      const vault1Address = await threeAVaultFactory.vaultsByOwner(alice.address, 0);
      expect(vault1Address).to.not.equal(ZeroAddress);

      await threeAVaultFactory.connect(alice).createVault("test vault3");
      const vault2Address = await threeAVaultFactory.vaultsByOwner(alice.address, 1);
      const vault2 = await ethers.getContractAt("SmartVault", vault2Address);
      expect(await vault2.name()).to.be.equal("test vault3");
      expect(await vault2.factory()).to.be.equal(threeAVaultFactory);
      expect(await vault2.stable()).to.be.equal(rwaUSD);
    });

    it("check the ability to set token price feed", async function () {
      const { tokenToPriceFeed } = await loadFixture(getMocked3adao);

      const testUSDC = await shared.deloyTestERC20("Test USD Coin", "tUSDC", 6);

      const tokenPrice = parseUnits("1", 6);
      const priceFeed = await shared.addTestPriceFeed(
        tokenToPriceFeed,
        testUSDC,
        tokenPrice,
      );

      expect(await priceFeed.price()).to.be.equal(tokenPrice);
      expect(await priceFeed.pricePoint()).to.be.equal(tokenPrice);

      expect(await tokenToPriceFeed.tokenPrice(testUSDC)).to.be.equal(tokenPrice);
      expect(await tokenToPriceFeed.tokenPriceFeed(testUSDC)).to.be.equal(priceFeed);

      // token.mcr = (DECIMAL_PRECISION * _mcr) / 100;
      // token.mlr = (DECIMAL_PRECISION * _mlr) / 100;
      expect(await tokenToPriceFeed.mcr(testUSDC)).to.be.equal(parseEther("1"));
      expect(await tokenToPriceFeed.mlr(testUSDC)).to.be.equal(parseEther("1"));

      expect(await tokenToPriceFeed.decimals(testUSDC)).to.be.equal(6);
      expect(await tokenToPriceFeed.borrowRate(testUSDC)).to.be.equal(0n);
    });

    it("it should be possible to add collateral to vault", async function () {
      const { threeAVaultFactory, tokenToPriceFeed, testVault, alice } = await loadFixture(getMocked3adao);

      const collateralAmount = parseEther("100");
      const testUSDC = await shared.deloyTestERC20("Test USD Coin", "tUSDC", 18);
      await testUSDC.mint(alice, collateralAmount);

      await expect(threeAVaultFactory.addCollateral(testVault, testUSDC, 0n))
        .to.revertedWith("collateral-not-supported");

      const tokenPrice = parseUnits("1", 18);
      await shared.addTestPriceFeed(
        tokenToPriceFeed,
        testUSDC,
        tokenPrice,
      );

      expect(await threeAVaultFactory.isCollateralSupported(testUSDC)).to.equal(true);

      await expect(threeAVaultFactory.addCollateral(testVault, testUSDC, 0n))
        .to.revertedWith("amount-is-0");

      await expect(threeAVaultFactory.addCollateral(testVault, testUSDC, collateralAmount))
        .to.revertedWith("collateral-cap-reached");

      await threeAVaultFactory.setCollateralCapacity(testUSDC, collateralAmount);

      await testUSDC.connect(alice).approve(threeAVaultFactory, collateralAmount);
      await threeAVaultFactory.connect(alice).addCollateral(
        testVault,
        testUSDC,
        collateralAmount,
      );
    });

    it("it should be possible to borrow rwaUSD", async function () {
      const { rwaUSD, threeAVaultFactory, tokenToPriceFeed, testVault, owner, alice } = await loadFixture(getMocked3adao);

      const collateralAmount = parseEther("100");
      const borrowAmount = collateralAmount;

      const testUSDC = await shared.deloyTestERC20("Test USD Coin", "tUSDC", 18);
      await testUSDC.mint(owner, collateralAmount);

      await threeAVaultFactory.setCollateralCapacity(testUSDC, collateralAmount);

      const tokenPrice = parseUnits("1", 18);
      await shared.addTestPriceFeed(
        tokenToPriceFeed,
        testUSDC,
        tokenPrice,
      );

      await expect(threeAVaultFactory.borrow(testVault, borrowAmount, alice))
        .to.revertedWith("not-enough-borrowable");

      await testUSDC.approve(threeAVaultFactory, collateralAmount);
      await threeAVaultFactory.addCollateral(
        testVault,
        testUSDC,
        collateralAmount,
      );

      const { 0: maxBorrowable, 1: borrowable } = await testVault.borrowable();
      expect(maxBorrowable).to.be.equal(collateralAmount);
      expect(borrowable).to.be.equal(collateralAmount);

      await threeAVaultFactory.borrow(testVault, borrowAmount, alice);

      expect(await rwaUSD.balanceOf(alice)).to.be.equal(borrowAmount);

      expect(await testVault.healthFactor(true)).to.be.equal(parseEther("1"));
      expect(await testVault.healthFactor(false)).to.be.equal(parseEther("1"));

      await expect(threeAVaultFactory.liquidate(testVault))
        .to.revertedWith("liquidation-factor-above-1");
    });
  });
});
