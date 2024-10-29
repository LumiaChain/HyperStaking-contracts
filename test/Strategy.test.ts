import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { parseEther, ZeroAddress } from "ethers";

import HyperStakingModule from "../ignition/modules/HyperStaking";
import PirexMockModule from "../ignition/modules/PirexMock";
import DineroStrategyModule from "../ignition/modules/DineroStrategy";
import { PirexEth } from "../typechain-types";

import * as shared from "./shared";

describe("Strategy", function () {
  async function getMockedPirex() {
    const [, , rewardRecipient] = await hre.ethers.getSigners();
    const { pxEth, upxEth, pirexEth, autoPxEth } = await hre.ignition.deploy(PirexMockModule);

    // increase rewards buffer
    await (pirexEth.connect(rewardRecipient) as PirexEth).harvest(await ethers.provider.getBlockNumber(), { value: parseEther("100") });

    return { pxEth, upxEth, pirexEth, autoPxEth };
  }

  async function deployHyperStaking() {
    const [owner, stakingManager, strategyVaultManager, alice, bob] = await hre.ethers.getSigners();
    const { diamond, staking, vault } = await hre.ignition.deploy(HyperStakingModule);

    // --------------------- Deploy Tokens ----------------------

    const testWstETH = await shared.deloyTestERC20("Test Wrapped Liquid Staked ETH", "tWstETH");

    // ------------------ Create Staking Pools ------------------

    const { nativeTokenAddress, ethPoolId } = await shared.createNativeStakingPool(staking);

    // -------------------- Apply Strategies --------------------

    // strategy asset price to eth 2:1
    const reserveAssetPrice = parseEther("2");

    const reserveStrategy = await shared.createReserveStrategy(
      diamond, nativeTokenAddress, await testWstETH.getAddress(), reserveAssetPrice,
    );

    const reserveStrategyAssetSupply = parseEther("55");
    await testWstETH.approve(reserveStrategy.target, reserveStrategyAssetSupply);
    await reserveStrategy.supplyRevenueAsset(reserveStrategyAssetSupply);

    await vault.connect(strategyVaultManager).addStrategy(ethPoolId, reserveStrategy, testWstETH);

    const { pxEth, upxEth, pirexEth, autoPxEth } = await loadFixture(getMockedPirex);
    const { dineroStrategy } = await hre.ignition.deploy(DineroStrategyModule, {
      parameters: {
        DineroStrategyModule: {
          diamond: await diamond.getAddress(),
          pxEth: await pxEth.getAddress(),
          pirexEth: await pirexEth.getAddress(),
          autoPxEth: await autoPxEth.getAddress(),
        },
      },
    });

    await vault.connect(strategyVaultManager).addStrategy(ethPoolId, dineroStrategy, autoPxEth);

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, vault, // diamond facets
      pxEth, upxEth, pirexEth, autoPxEth, // pirex mock
      testWstETH, reserveStrategy, dineroStrategy, // test contracts
      ethPoolId, // ids
      reserveAssetPrice, reserveStrategyAssetSupply, // values
      nativeTokenAddress, owner, stakingManager, strategyVaultManager, alice, bob, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("ReserveStrategy", function () {
    it("check state after allocation", async function () {
      const {
        staking, vault, testWstETH, ethPoolId, reserveStrategy, reserveAssetPrice, owner, alice,
      } = await loadFixture(deployHyperStaking);

      const ownerAmount = parseEther("2");
      const aliceAmount = parseEther("8");

      expect(await testWstETH.balanceOf(vault.target)).to.equal(0);
      expect(await reserveStrategy.assetPrice()).to.equal(parseEther("2"));

      // event
      await expect(staking.stakeDeposit(ethPoolId, reserveStrategy, ownerAmount, owner, { value: ownerAmount }))
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(owner.address, ownerAmount, ownerAmount * parseEther("1") / reserveAssetPrice);

      expect(await testWstETH.balanceOf(vault.target)).to.equal(ownerAmount * parseEther("1") / reserveAssetPrice);

      // event
      await expect(staking.stakeDeposit(
        ethPoolId, reserveStrategy, aliceAmount, alice, { value: aliceAmount }),
      )
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(alice.address, aliceAmount, aliceAmount * parseEther("1") / reserveAssetPrice);

      // UserInfo
      expect(
        (await vault.userVaultInfo(reserveStrategy, owner.address)).stakeLocked,
      ).to.equal(ownerAmount);

      // UserInfo
      expect((await staking.userPoolInfo(ethPoolId, owner.address)).staked).to.equal(ownerAmount);
      expect((await vault.userVaultInfo(reserveStrategy, owner.address)).stakeLocked).to.equal(ownerAmount);
      expect(await vault.userContribution(reserveStrategy, owner.address)).to.equal(parseEther("0.2"));
      // ---
      expect((await staking.userPoolInfo(ethPoolId, alice.address)).staked).to.equal(aliceAmount);
      expect((await vault.userVaultInfo(reserveStrategy, alice.address)).stakeLocked).to.equal(aliceAmount);
      expect(await vault.userContribution(reserveStrategy, alice.address)).to.equal(parseEther("0.8")); // 80%
      // VaultInfo
      expect((await vault.vaultInfo(reserveStrategy)).strategy).to.equal(reserveStrategy);
      expect((await vault.vaultInfo(reserveStrategy)).poolId).to.equal(ethPoolId);
      expect((await vault.vaultInfo(reserveStrategy)).totalStakeLocked).to.equal(ownerAmount + aliceAmount);
      // AssetInfo
      expect((await vault.vaultAssetInfo(reserveStrategy)).asset).to.equal(testWstETH.target);
      expect((await vault.vaultAssetInfo(reserveStrategy)).totalShares)
        .to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);

      expect(await testWstETH.balanceOf(vault.target)).to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);
    });

    it("check state after exit", async function () {
      const {
        staking, vault, testWstETH, ethPoolId, reserveStrategy, reserveAssetPrice, owner,
      } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("2.4");
      const withdrawAmount = parseEther("0.6");
      const diffAmount = stakeAmount - withdrawAmount;

      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, owner, { value: stakeAmount });

      // event
      await expect(staking.stakeWithdraw(ethPoolId, reserveStrategy, withdrawAmount, owner))
        .to.emit(reserveStrategy, "Exit")
        .withArgs(owner.address, withdrawAmount * parseEther("1") / reserveAssetPrice, withdrawAmount);

      // UserInfo
      expect((await staking.userPoolInfo(ethPoolId, owner.address)).staked).to.equal(diffAmount);
      expect((await vault.userVaultInfo(reserveStrategy, owner.address)).stakeLocked).to.equal(diffAmount);

      expect(await vault.userContribution(reserveStrategy, owner.address)).to.equal(parseEther("1"));

      // UserInfo
      expect((await staking.userPoolInfo(ethPoolId, owner.address)).staked).to.equal(diffAmount);
      expect((await vault.userVaultInfo(reserveStrategy, owner.address)).stakeLocked).to.equal(diffAmount);
      expect(await vault.userContribution(reserveStrategy, owner.address)).to.equal(parseEther("1"));
      // VaultInfo
      expect((await vault.vaultInfo(reserveStrategy)).totalStakeLocked).to.equal(diffAmount);
      // AssetInfo
      expect((await vault.vaultAssetInfo(reserveStrategy)).asset).to.equal(testWstETH.target);

      expect((await vault.vaultAssetInfo(reserveStrategy)).totalShares)
        .to.equal(diffAmount * parseEther("1") / reserveAssetPrice);
      expect(await testWstETH.balanceOf(vault.target)).to.equal(diffAmount * parseEther("1") / reserveAssetPrice);

      // withdraw all
      await staking.stakeWithdraw(ethPoolId, reserveStrategy, diffAmount, owner);

      // UserInfo
      expect((await staking.userPoolInfo(ethPoolId, owner.address)).staked).to.equal(0);
      expect((await vault.userVaultInfo(reserveStrategy, owner.address)).stakeLocked).to.equal(0);
      expect(await vault.userContribution(reserveStrategy, owner.address)).to.equal(0);
      // VaultInfo
      expect((await vault.vaultInfo(reserveStrategy)).totalStakeLocked).to.equal(0);
      // AssetInfo
      expect((await vault.vaultAssetInfo(reserveStrategy)).asset).to.equal(testWstETH.target);
      expect((await vault.vaultAssetInfo(reserveStrategy)).totalShares).to.equal(0);
      expect(await testWstETH.balanceOf(vault.target)).to.equal(0);
    });

    describe("Errors", function () {
      it("OnlyStrategyVaultManager", async function () {
        const { vault, ethPoolId, reserveStrategy, alice } = await loadFixture(deployHyperStaking);

        await expect(vault.addStrategy(ethPoolId, reserveStrategy, ZeroAddress))
          .to.be.reverted;

        await expect(vault.connect(alice).addStrategy(ethPoolId, reserveStrategy, ZeroAddress))
          // .to.be.revertedWithCustomError(vault, "OnlyStrategyVaultManager");
          .to.be.reverted;
      });

      it("VaultDoesNotExist", async function () {
        const { staking, ethPoolId, owner } = await loadFixture(deployHyperStaking);

        const badStrategy = "0x36fD7e46150d3C0Be5741b0fc8b0b2af4a0D4Dc5";

        await expect(staking.stakeDeposit(ethPoolId, badStrategy, 1, owner, { value: 1 }))
          .to.be.revertedWithCustomError(staking, "VaultDoesNotExist");
      });

      it("VaultAlreadyExist", async function () {
        const { vault, strategyVaultManager, ethPoolId, reserveStrategy } = await loadFixture(deployHyperStaking);

        const randomToken = "0x8Da05a7A689c2C054246B186bEe1C75fcD1df0bC";

        await expect(vault.connect(strategyVaultManager).addStrategy(ethPoolId, reserveStrategy, randomToken))
          .to.be.revertedWithCustomError(vault, "VaultAlreadyExist");
      });

      it("Vault external functions not be accessible without staking", async function () {
        const { vault, reserveStrategy, alice } = await loadFixture(deployHyperStaking);

        await expect(vault.deposit(reserveStrategy, alice, 1000))
          .to.be.reverted;

        await expect(vault.withdraw(reserveStrategy, alice, 1000))
          .to.be.reverted;
      });
    });
  });

  describe("Dinero Strategy", function () {
    it("staking deposit to dinero strategy should aquire apxEth", async function () {
      const { staking, vault, autoPxEth, ethPoolId, dineroStrategy, owner } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("8");

      const expectedFee = 0n;
      const expectedAsset = stakeAmount - expectedFee;
      const expectedShares = autoPxEth.convertToShares(expectedAsset);

      // event
      await expect(staking.stakeDeposit(ethPoolId, dineroStrategy, stakeAmount, owner, { value: stakeAmount }))
        .to.emit(dineroStrategy, "Allocate")
        .withArgs(
          owner.address,
          expectedAsset,
          expectedShares,
        );

      expect((await staking.userPoolInfo(ethPoolId, owner)).staked).to.equal(stakeAmount);

      expect((await vault.vaultInfo(dineroStrategy)).totalStakeLocked).to.equal(stakeAmount);
      expect((await vault.vaultAssetInfo(dineroStrategy)).asset).to.equal(autoPxEth.target);
      expect((await vault.vaultAssetInfo(dineroStrategy)).totalShares).to.equal(stakeAmount);

      expect(await autoPxEth.balanceOf(vault.target)).to.equal(stakeAmount);
    });

    it("unstaking from to dinero strategy should exchange apxEth back to eth", async function () {
      const { staking, vault, autoPxEth, ethPoolId, dineroStrategy, owner } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("3");
      await staking.stakeDeposit(ethPoolId, dineroStrategy, stakeAmount, owner, { value: stakeAmount });

      await expect(staking.stakeWithdraw(ethPoolId, dineroStrategy, stakeAmount, owner))
        .to.emit(dineroStrategy, "Exit")
        .withArgs(owner.address, stakeAmount, anyValue);

      expect((await staking.userPoolInfo(ethPoolId, owner.address)).staked).to.equal(0);

      expect((await vault.userVaultInfo(dineroStrategy, owner.address)).stakeLocked).to.equal(0);
      expect((await vault.vaultInfo(dineroStrategy)).totalStakeLocked).to.equal(0);
      expect((await vault.vaultAssetInfo(dineroStrategy)).asset).to.equal(autoPxEth.target);
      expect((await vault.vaultAssetInfo(dineroStrategy)).totalShares).to.equal(0);

      expect(await autoPxEth.balanceOf(vault.target)).to.equal(0);
    });
  });

  describe("Pirex Mock", function () {
    it("it should be possible to deposit ETH and get pxETH", async function () {
      const [owner] = await hre.ethers.getSigners();
      const { pxEth, pirexEth } = await loadFixture(getMockedPirex);

      await pirexEth.deposit(owner.address, false, { value: parseEther("1") });

      expect(await pxEth.balanceOf(owner.address)).to.be.greaterThan(0);
    });

    it("it should be possible to deposit ETH and auto-compund it with apxEth", async function () {
      const [owner] = await hre.ethers.getSigners();
      const { pxEth, pirexEth, autoPxEth } = await loadFixture(getMockedPirex);

      await pirexEth.deposit(owner.address, true, { value: parseEther("5") });

      expect(await pxEth.balanceOf(owner.address)).to.equal(0);
      expect(await autoPxEth.balanceOf(owner.address)).to.be.greaterThan(0);
    });

    it("it should be possible to instant Redeem apxEth back to ETH", async function () {
      const [owner, alice] = await hre.ethers.getSigners();
      const { pxEth, pirexEth, autoPxEth } = await loadFixture(getMockedPirex);

      const initialDeposit = parseEther("1");
      await pirexEth.deposit(owner.address, true, { value: initialDeposit });

      const totalAssets = await autoPxEth.totalAssets();
      await autoPxEth.withdraw(totalAssets / 2n, owner.address, owner.address);

      await expect(pirexEth.instantRedeemWithPxEth(initialDeposit / 2n, alice.address))
        .to.changeEtherBalances(
          [pirexEth, alice],
          [-initialDeposit / 2n, initialDeposit / 2n],
        );

      expect(await pxEth.balanceOf(owner.address)).to.equal(0);
    });
  });
});
