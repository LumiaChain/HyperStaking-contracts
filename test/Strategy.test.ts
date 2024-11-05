import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { parseEther, parseUnits, TransactionResponse, ZeroAddress } from "ethers";

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
    const [owner, stakingManager, strategyVaultManager, bob, alice] = await hre.ethers.getSigners();
    const { diamond, staking, vault } = await hre.ignition.deploy(HyperStakingModule);

    // --------------------- Deploy Tokens ----------------------

    const testWstETH = await shared.deloyTestERC20("Test Wrapped Liquid Staked ETH", "tWstETH");

    // ------------------ Create Staking Pools ------------------

    const { nativeTokenAddress, ethPoolId } = await shared.createNativeStakingPool(staking);

    // -------------------- Apply Strategies --------------------

    const defaultRevenueFee = parseEther("0"); // 0% fee

    // strategy asset price to eth 2:1
    const reserveAssetPrice = parseEther("2");

    const reserveStrategy = await shared.createReserveStrategy(
      diamond, nativeTokenAddress, await testWstETH.getAddress(), reserveAssetPrice,
    );

    await vault.connect(strategyVaultManager).addStrategy(
      ethPoolId,
      reserveStrategy,
      testWstETH,
      defaultRevenueFee,
    );

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

    await vault.connect(strategyVaultManager).addStrategy(
      ethPoolId,
      dineroStrategy,
      autoPxEth,
      defaultRevenueFee,
    );

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, vault, // diamond facets
      pxEth, upxEth, pirexEth, autoPxEth, // pirex mock
      testWstETH, reserveStrategy, dineroStrategy, // test contracts
      ethPoolId, // ids
      defaultRevenueFee, reserveAssetPrice, // values
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
      expect(await reserveStrategy.assetPrice()).to.equal(reserveAssetPrice);
      expect(await reserveStrategy.convertToAllocation(ownerAmount)).to.equal(ownerAmount * parseEther("1") / reserveAssetPrice);

      // event
      await expect(staking.stakeDeposit(ethPoolId, reserveStrategy, ownerAmount, owner, { value: ownerAmount }))
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(owner.address, ownerAmount, ownerAmount * parseEther("1") / reserveAssetPrice);

      expect(await testWstETH.balanceOf(vault.target)).to.equal(ownerAmount * parseEther("1") / reserveAssetPrice);

      // event
      await expect(staking.stakeDeposit(ethPoolId, reserveStrategy, aliceAmount, alice, { value: aliceAmount }))
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(alice.address, aliceAmount, aliceAmount * parseEther("1") / reserveAssetPrice);

      // Owner UserInfo
      expect((await staking.userPoolInfo(ethPoolId, owner)).staked).to.equal(ownerAmount);
      expect((await staking.userPoolInfo(ethPoolId, owner)).stakeLocked).to.equal(ownerAmount);
      expect((await vault.userVaultInfo(reserveStrategy, owner)).stakeLocked).to.equal(ownerAmount);
      expect((await vault.userVaultInfo(reserveStrategy, owner)).allocationPoint).to.equal(parseUnits("1", 36) / reserveAssetPrice);
      expect(await vault.userContribution(reserveStrategy, owner)).to.equal(parseEther("0.2"));

      // Alice UserInfo
      expect((await staking.userPoolInfo(ethPoolId, alice)).staked).to.equal(aliceAmount);
      expect((await staking.userPoolInfo(ethPoolId, alice)).stakeLocked).to.equal(aliceAmount);
      expect((await vault.userVaultInfo(reserveStrategy, alice)).stakeLocked).to.equal(aliceAmount);
      expect((await vault.userVaultInfo(reserveStrategy, alice)).allocationPoint)
        .to.equal(await reserveStrategy.convertToAllocation(parseEther("1")));
      expect(await vault.userContribution(reserveStrategy, alice)).to.equal(parseEther("0.8")); // 80%

      // VaultInfo
      expect((await vault.vaultInfo(reserveStrategy)).strategy).to.equal(reserveStrategy);
      expect((await vault.vaultInfo(reserveStrategy)).poolId).to.equal(ethPoolId);
      expect((await vault.vaultInfo(reserveStrategy)).asset).to.equal(testWstETH);

      // TiersInfo
      expect((await vault.vaultTier1Info(reserveStrategy)).assetAllocation).to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);
      expect((await vault.vaultTier1Info(reserveStrategy)).totalStakeLocked).to.equal(ownerAmount + aliceAmount);
      expect((await vault.vaultTier1Info(reserveStrategy)).revenueFee).to.equal(0);

      expect((await vault.vaultTier2Info(reserveStrategy)).vaultToken).to.not.equal(ZeroAddress);

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
      expect((await staking.userPoolInfo(ethPoolId, owner)).staked).to.equal(diffAmount);
      expect((await staking.userPoolInfo(ethPoolId, owner)).stakeLocked).to.equal(diffAmount);

      expect((await vault.userVaultInfo(reserveStrategy, owner)).stakeLocked).to.equal(diffAmount);
      expect((await vault.userVaultInfo(reserveStrategy, owner)).allocationPoint)
        .to.equal(await reserveStrategy.convertToAllocation(parseEther("1")));
      expect(await vault.userContribution(reserveStrategy, owner)).to.equal(parseEther("1"));

      // TiersInfo
      expect((await vault.vaultTier1Info(reserveStrategy)).assetAllocation).to.equal(diffAmount * parseEther("1") / reserveAssetPrice);
      expect((await vault.vaultTier1Info(reserveStrategy)).totalStakeLocked).to.equal(diffAmount);

      expect(await testWstETH.balanceOf(vault.target)).to.equal(diffAmount * parseEther("1") / reserveAssetPrice);

      // withdraw all
      await staking.stakeWithdraw(ethPoolId, reserveStrategy, diffAmount, owner);

      // UserInfo
      expect((await staking.userPoolInfo(ethPoolId, owner)).staked).to.equal(0);
      expect((await staking.userPoolInfo(ethPoolId, owner)).stakeLocked).to.equal(0);

      expect((await vault.userVaultInfo(reserveStrategy, owner)).stakeLocked).to.equal(0);
      expect((await vault.userVaultInfo(reserveStrategy, owner)).allocationPoint).to.equal(parseUnits("1", 36) / reserveAssetPrice);
      expect(await vault.userContribution(reserveStrategy, owner)).to.equal(0);

      // TiersInfo
      expect((await vault.vaultTier1Info(reserveStrategy)).assetAllocation).to.equal(0);
      expect((await vault.vaultTier1Info(reserveStrategy)).totalStakeLocked).to.equal(0);

      expect(await testWstETH.balanceOf(vault.target)).to.equal(0);
    });

    it("allocation point should depend on weighted price", async function () {
      const {
        staking, vault, ethPoolId, reserveStrategy, owner,
      } = await loadFixture(deployHyperStaking);

      // reverse asset:eth to eth:asset price
      const reversePrice = (amount: bigint) => parseUnits("1", 36) / amount;

      const price1 = parseEther("1");
      const price2 = parseEther("2");
      const price3 = parseEther("3.5");

      const stakeAmount1 = parseEther("2.0");
      const stakeAmount2 = parseEther("2.0");
      const stakeAmount3 = parseEther("9.0");

      await reserveStrategy.setAssetPrice(price1);
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount1, owner, { value: stakeAmount1 });

      // just the same as price1
      expect((await vault.userVaultInfo(reserveStrategy, owner)).allocationPoint).to.equal(price1);

      await reserveStrategy.setAssetPrice(price2);
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount2, owner, { value: stakeAmount2 });

      expect((await vault.userVaultInfo(reserveStrategy, owner)).allocationPoint)
        .to.equal((reversePrice(price1) * stakeAmount1 + reversePrice(price2) * stakeAmount2) / (stakeAmount1 + stakeAmount2));

      await reserveStrategy.setAssetPrice(price3);
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount3, owner, { value: stakeAmount3 });

      const expectedPrice = // weighted average
        (reversePrice(price1) * stakeAmount1 + reversePrice(price2) * stakeAmount2 + reversePrice(price3) * stakeAmount3) /
        (stakeAmount1 + stakeAmount2 + stakeAmount3);

      expect((await vault.userVaultInfo(reserveStrategy, owner)).allocationPoint)
        .to.equal(expectedPrice);
    });

    it("user generates revenue when asset increases in price", async function () {
      const {
        staking, vault, ethPoolId, reserveStrategy, alice,
      } = await loadFixture(deployHyperStaking);

      const price1 = parseEther("2");
      const price2 = parseEther("4");

      const stakeAmount = parseEther("3.0");

      await reserveStrategy.setAssetPrice(price1);
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      // increase price
      await reserveStrategy.setAssetPrice(price2);

      const expectedRevenue = stakeAmount * price2 / price1 - stakeAmount;

      expect(await vault.userRevenue(reserveStrategy, alice)).to.equal(expectedRevenue);

      // revenue should decrease proportionaly to withdraw
      await staking.connect(alice).stakeWithdraw(ethPoolId, reserveStrategy, stakeAmount / 2n, alice);

      expect(await vault.userRevenue(reserveStrategy, alice)).to.equal(expectedRevenue / 2n);
    });

    it("users revenue should work with a more complex scenario", async function () {
      const {
        staking, vault, ethPoolId, reserveStrategy, bob, alice,
      } = await loadFixture(deployHyperStaking);

      const price1 = parseEther("1");
      const price2 = parseEther("2");
      const price3 = parseEther("4");

      const stakeAmount = parseEther("2.0");

      await reserveStrategy.setAssetPrice(price1);
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, bob, { value: stakeAmount });

      await reserveStrategy.setAssetPrice(price2);

      // alice jonis after first price increase, and bob increase his stake
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, bob, { value: stakeAmount });

      await reserveStrategy.setAssetPrice(price3);

      const expectedAliceRevenue = stakeAmount * price3 / price2 - stakeAmount;
      expect(await vault.userRevenue(reserveStrategy, alice)).to.equal(expectedAliceRevenue);

      // bob revenue should reflect both price increases
      const expectedBobRevenue =
        (stakeAmount * price3) / price1 +
        (stakeAmount * price3) / price2 - 2n * stakeAmount;
      expect(await vault.userRevenue(reserveStrategy, bob)).to.equal(expectedBobRevenue);
    });

    it("vault manager should be able to set revenue fee", async function () {
      const {
        vault, reserveStrategy, strategyVaultManager,
      } = await loadFixture(deployHyperStaking);

      const bigFee = parseEther("0.21"); // 21%
      const newFee = parseEther("0.1"); // 10%

      await expect(vault.setTier1RevenueFee(reserveStrategy, newFee))
        .to.be.reverted;

      await expect(vault.connect(strategyVaultManager).setTier1RevenueFee(reserveStrategy, bigFee))
        .to.be.revertedWithCustomError(vault, "InvalidRevenueFeeValue");

      // OK
      await expect(vault.connect(strategyVaultManager).setTier1RevenueFee(reserveStrategy, newFee));
    });

    it("revenue fee value should be distracted when withdraw his stake", async function () {
      const {
        staking, vault, ethPoolId, reserveStrategy, alice, strategyVaultManager,
      } = await loadFixture(deployHyperStaking);

      let tx: TransactionResponse;
      let transactionCosts = 0n;
      const includeTransactionCosts = async (tx: TransactionResponse): Promise<void> => {
        const receipt = await tx.wait();
        transactionCosts += receipt!.cumulativeGasUsed * tx.gasPrice;
      };

      const revenueFee = parseEther("0.1"); // 10%
      await vault.connect(strategyVaultManager).setTier1RevenueFee(reserveStrategy, revenueFee);

      const price1 = parseEther("2");
      const price2 = parseEther("2.5");
      const stakeAmount = parseEther("3.0");

      const aliceBalanceBefore = await ethers.provider.getBalance(alice.address);

      await reserveStrategy.setAssetPrice(price1);
      tx = await staking.connect(alice).stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });
      await includeTransactionCosts(tx);

      await reserveStrategy.setAssetPrice(price2);
      const revenue = stakeAmount * price2 / price1 - stakeAmount;

      tx = await staking.connect(alice).stakeWithdraw(ethPoolId, reserveStrategy, stakeAmount, alice);
      await includeTransactionCosts(tx);

      const expectedFee = revenueFee * revenue / parseEther("1");

      // alice balance after
      const expectedAliceBalance = aliceBalanceBefore + revenue - expectedFee - transactionCosts;
      expect(await ethers.provider.getBalance(alice.address)).to.equal(expectedAliceBalance);
    });

    describe("Errors", function () {
      it("OnlyStrategyVaultManager", async function () {
        const {
          vault, ethPoolId, reserveStrategy, alice, defaultRevenueFee,
        } = await loadFixture(deployHyperStaking);

        await expect(vault.addStrategy(ethPoolId, reserveStrategy, ZeroAddress, defaultRevenueFee))
          .to.be.reverted;

        await expect(vault.connect(alice).addStrategy(
          ethPoolId,
          reserveStrategy,
          ZeroAddress,
          defaultRevenueFee,
        ))
          // hardhat unfortunately does not recognize custom errors from child contracts
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
        const {
          vault, strategyVaultManager, ethPoolId, reserveStrategy, defaultRevenueFee,
        } = await loadFixture(deployHyperStaking);

        const randomToken = "0x8Da05a7A689c2C054246B186bEe1C75fcD1df0bC";

        await expect(vault.connect(strategyVaultManager).addStrategy(
          ethPoolId,
          reserveStrategy,
          randomToken,
          defaultRevenueFee,
        ))
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
      const apxEthPrice = parseEther("1");

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
      expect((await vault.vaultInfo(dineroStrategy)).asset).to.equal(autoPxEth.target);

      expect((await vault.vaultTier1Info(dineroStrategy)).assetAllocation).to.equal(stakeAmount * apxEthPrice / parseEther("1"));
      expect((await vault.vaultTier1Info(dineroStrategy)).totalStakeLocked).to.equal(stakeAmount);

      expect(await autoPxEth.balanceOf(vault.target)).to.equal(stakeAmount * apxEthPrice / parseEther("1"));
    });

    it("unstaking from to dinero strategy should exchange apxEth back to eth", async function () {
      const { staking, vault, autoPxEth, ethPoolId, dineroStrategy, owner } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("3");
      const apxEthPrice = parseEther("1");

      await staking.stakeDeposit(ethPoolId, dineroStrategy, stakeAmount, owner, { value: stakeAmount });

      await expect(staking.stakeWithdraw(ethPoolId, dineroStrategy, stakeAmount, owner))
        .to.emit(dineroStrategy, "Exit")
        .withArgs(owner.address, stakeAmount * apxEthPrice / parseEther("1"), anyValue);

      expect((await staking.userPoolInfo(ethPoolId, owner.address)).staked).to.equal(0);
      expect((await vault.userVaultInfo(dineroStrategy, owner.address)).stakeLocked).to.equal(0);
      expect((await vault.vaultInfo(dineroStrategy)).asset).to.equal(autoPxEth.target);

      expect((await vault.vaultTier1Info(dineroStrategy)).assetAllocation).to.equal(0);
      expect((await vault.vaultTier1Info(dineroStrategy)).totalStakeLocked).to.equal(0);

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
