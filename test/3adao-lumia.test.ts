import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers, ignition } from "hardhat";
import { parseEther, parseUnits, ZeroAddress } from "ethers";

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
