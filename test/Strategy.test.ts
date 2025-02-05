import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, ignition } from "hardhat";
import { parseEther, parseUnits, ZeroAddress } from "ethers";

import DineroStrategyModule from "../ignition/modules/DineroStrategy";
import PirexMockModule from "../ignition/modules/test/PirexMock";

import * as shared from "./shared";
import TxCostTracker from "./txCostTracker";
import { PirexEth } from "../typechain-types";
import { CurrencyStruct } from "../typechain-types/contracts/hyperstaking/facets/VaultFactoryFacet";

describe("Strategy", function () {
  async function getMockedPirex() {
    const [, , rewardRecipient] = await ethers.getSigners();
    const { pxEth, upxEth, pirexEth, autoPxEth } = await ignition.deploy(PirexMockModule);

    // increase rewards buffer
    await (pirexEth.connect(rewardRecipient) as PirexEth).harvest(await ethers.provider.getBlockNumber(), { value: parseEther("100") });

    return { pxEth, upxEth, pirexEth, autoPxEth };
  }

  async function deployHyperStaking() {
    const [owner, stakingManager, strategyVaultManager, bob, alice] = await ethers.getSigners();

    // -------------------- Deploy Tokens --------------------

    const testWstETH = await shared.deloyTestERC20("Test Wrapped Liquid Staked ETH", "tWstETH");
    const erc4626Vault = await shared.deloyTestERC4626Vault(testWstETH);

    // --------------------- Hyperstaking Diamond --------------------

    const { diamond, staking, vaultFactory, tier1, tier2 } = await shared.deployTestHyperStaking(0n, erc4626Vault);

    // -------------------- Apply Strategies --------------------

    const defaultRevenueFee = parseEther("0"); // 0% fee

    // strategy asset price to eth 2:1
    const reserveAssetPrice = parseEther("2");

    const reserveStrategy = await shared.createReserveStrategy(
      diamond, shared.nativeTokenAddress, await testWstETH.getAddress(), reserveAssetPrice,
    );

    await vaultFactory.connect(strategyVaultManager).addStrategy(
      reserveStrategy,
      "eth reserve vault1",
      "rETH1",
      defaultRevenueFee,
    );

    const { pxEth, upxEth, pirexEth, autoPxEth } = await loadFixture(getMockedPirex);
    const { dineroStrategy } = await ignition.deploy(DineroStrategyModule, {
      parameters: {
        DineroStrategyModule: {
          diamond: await diamond.getAddress(),
          pxEth: await pxEth.getAddress(),
          pirexEth: await pirexEth.getAddress(),
          autoPxEth: await autoPxEth.getAddress(),
        },
      },
    });

    await vaultFactory.connect(strategyVaultManager).addStrategy(
      dineroStrategy,
      "eth vault2",
      "dETH2",
      defaultRevenueFee,
    );

    // ----------------------------------------

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, vaultFactory, tier1, tier2, // diamond facets
      pxEth, upxEth, pirexEth, autoPxEth, // pirex mock
      testWstETH, reserveStrategy, dineroStrategy, // test contracts
      defaultRevenueFee, reserveAssetPrice, // values
      owner, stakingManager, strategyVaultManager, alice, bob, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("ReserveStrategy", function () {
    it("check state after allocation", async function () {
      const {
        staking, vaultFactory, tier1, tier2, testWstETH, reserveStrategy, reserveAssetPrice, owner, alice,
      } = await loadFixture(deployHyperStaking);

      const ownerAmount = parseEther("2");
      const aliceAmount = parseEther("8");

      expect(await testWstETH.balanceOf(vaultFactory)).to.equal(0);
      expect(await reserveStrategy.assetPrice()).to.equal(reserveAssetPrice);
      expect(await reserveStrategy.previewAllocation(ownerAmount)).to.equal(ownerAmount * parseEther("1") / reserveAssetPrice);

      // event
      await expect(staking.stakeDeposit(reserveStrategy, ownerAmount, owner, { value: ownerAmount }))
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(owner, ownerAmount, ownerAmount * parseEther("1") / reserveAssetPrice);

      expect(await testWstETH.balanceOf(vaultFactory)).to.equal(ownerAmount * parseEther("1") / reserveAssetPrice);

      // event
      await expect(staking.stakeDeposit(reserveStrategy, aliceAmount, alice, { value: aliceAmount }))
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(alice, aliceAmount, aliceAmount * parseEther("1") / reserveAssetPrice);

      // Owner UserInfo
      expect((await tier1.userTier1Info(reserveStrategy, owner)).stake).to.equal(ownerAmount);
      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint).to.equal(parseUnits("1", 36) / reserveAssetPrice);
      expect(await tier1.userContribution(reserveStrategy, owner)).to.equal(parseEther("0.2"));

      // Alice UserInfo
      expect((await tier1.userTier1Info(reserveStrategy, alice)).stake).to.equal(aliceAmount);
      expect((await tier1.userTier1Info(reserveStrategy, alice)).allocationPoint)
        .to.equal(await reserveStrategy.previewAllocation(parseEther("1")));
      expect(await tier1.userContribution(reserveStrategy, alice)).to.equal(parseEther("0.8")); // 80%

      // VaultInfo
      expect((await vaultFactory.vaultInfo(reserveStrategy)).stakeCurrency).to.deep.equal([shared.nativeTokenAddress]);
      expect((await vaultFactory.vaultInfo(reserveStrategy)).strategy).to.equal(reserveStrategy);
      expect((await vaultFactory.vaultInfo(reserveStrategy)).asset).to.equal(testWstETH);

      // TiersInfo
      expect((await tier1.vaultTier1Info(reserveStrategy)).assetAllocation).to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);
      expect((await tier1.vaultTier1Info(reserveStrategy)).totalStake).to.equal(ownerAmount + aliceAmount);
      expect((await tier1.vaultTier1Info(reserveStrategy)).revenueFee).to.equal(0);

      expect((await tier2.vaultTier2Info(reserveStrategy)).vaultToken).to.not.equal(ZeroAddress);

      expect(await testWstETH.balanceOf(vaultFactory)).to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);
    });

    it("check state after exit", async function () {
      const {
        staking, vaultFactory, tier1, testWstETH, reserveStrategy, reserveAssetPrice, owner,
      } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("2.4");
      const withdrawAmount = parseEther("0.6");
      const diffAmount = stakeAmount - withdrawAmount;

      await staking.stakeDeposit(reserveStrategy, stakeAmount, owner, { value: stakeAmount });

      // event
      await expect(staking.stakeWithdraw(reserveStrategy, withdrawAmount, owner))
        .to.emit(reserveStrategy, "Exit")
        .withArgs(owner, withdrawAmount * parseEther("1") / reserveAssetPrice, withdrawAmount);

      // UserInfo
      expect((await tier1.userTier1Info(reserveStrategy, owner)).stake).to.equal(diffAmount);
      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint)
        .to.equal(await reserveStrategy.previewAllocation(parseEther("1")));
      expect(await tier1.userContribution(reserveStrategy, owner)).to.equal(parseEther("1"));

      // TiersInfo
      expect((await tier1.vaultTier1Info(reserveStrategy)).assetAllocation).to.equal(diffAmount * parseEther("1") / reserveAssetPrice);
      expect((await tier1.vaultTier1Info(reserveStrategy)).totalStake).to.equal(diffAmount);

      expect(await testWstETH.balanceOf(vaultFactory)).to.equal(diffAmount * parseEther("1") / reserveAssetPrice);

      // withdraw all
      await staking.stakeWithdraw(reserveStrategy, diffAmount, owner);

      // UserInfo
      expect((await tier1.userTier1Info(reserveStrategy, owner)).stake).to.equal(0);
      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint).to.equal(parseUnits("1", 36) / reserveAssetPrice);
      expect(await tier1.userContribution(reserveStrategy, owner)).to.equal(0);

      // TiersInfo
      expect((await tier1.vaultTier1Info(reserveStrategy)).assetAllocation).to.equal(0);
      expect((await tier1.vaultTier1Info(reserveStrategy)).totalStake).to.equal(0);

      expect(await testWstETH.balanceOf(vaultFactory)).to.equal(0);
    });

    it("allocation point should depend on weighted price", async function () {
      const {
        staking, tier1, reserveStrategy, owner,
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
      await staking.stakeDeposit(reserveStrategy, stakeAmount1, owner, { value: stakeAmount1 });

      // just the same as price1
      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint).to.equal(price1);

      await reserveStrategy.setAssetPrice(price2);
      await staking.stakeDeposit(reserveStrategy, stakeAmount2, owner, { value: stakeAmount2 });

      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint)
        .to.equal((reversePrice(price1) * stakeAmount1 + reversePrice(price2) * stakeAmount2) / (stakeAmount1 + stakeAmount2));

      await reserveStrategy.setAssetPrice(price3);
      await staking.stakeDeposit(reserveStrategy, stakeAmount3, owner, { value: stakeAmount3 });

      const expectedPrice = // weighted average
        (reversePrice(price1) * stakeAmount1 + reversePrice(price2) * stakeAmount2 + reversePrice(price3) * stakeAmount3) /
        (stakeAmount1 + stakeAmount2 + stakeAmount3);

      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint)
        .to.equal(expectedPrice);
    });

    it("user generates revenue when asset increases in price", async function () {
      const { staking, tier1, reserveStrategy, alice } = await loadFixture(deployHyperStaking);

      const price1 = parseEther("2");
      const price2 = parseEther("4");

      const stakeAmount = parseEther("3.0");

      await reserveStrategy.setAssetPrice(price1);
      await staking.stakeDeposit(reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      // increase price
      await reserveStrategy.setAssetPrice(price2);

      const expectedRevenue = stakeAmount * price2 / price1 - stakeAmount;

      expect(await tier1.userRevenue(reserveStrategy, alice)).to.equal(expectedRevenue);

      // revenue should decrease proportionaly to withdraw
      await staking.connect(alice).stakeWithdraw(reserveStrategy, stakeAmount / 2n, alice);

      expect(await tier1.userRevenue(reserveStrategy, alice)).to.equal(expectedRevenue / 2n);
    });

    it("users revenue should work with a more complex scenario", async function () {
      const { staking, tier1, reserveStrategy, bob, alice } = await loadFixture(deployHyperStaking);

      const price1 = parseEther("1");
      const price2 = parseEther("2");
      const price3 = parseEther("4");

      const stakeAmount = parseEther("2.0");

      await reserveStrategy.setAssetPrice(price1);
      await staking.stakeDeposit(reserveStrategy, stakeAmount, bob, { value: stakeAmount });

      await reserveStrategy.setAssetPrice(price2);

      // alice jonis after first price increase, and bob increase his stake
      await staking.stakeDeposit(reserveStrategy, stakeAmount, alice, { value: stakeAmount });
      await staking.stakeDeposit(reserveStrategy, stakeAmount, bob, { value: stakeAmount });

      await reserveStrategy.setAssetPrice(price3);

      const expectedAliceRevenue = stakeAmount * price3 / price2 - stakeAmount;
      expect(await tier1.userRevenue(reserveStrategy, alice)).to.equal(expectedAliceRevenue);

      // bob revenue should reflect both price increases
      const expectedBobRevenue =
        (stakeAmount * price3) / price1 +
        (stakeAmount * price3) / price2 - 2n * stakeAmount;
      expect(await tier1.userRevenue(reserveStrategy, bob)).to.equal(expectedBobRevenue);
    });

    it("vault manager should be able to set revenue fee", async function () {
      const {
        tier1, reserveStrategy, strategyVaultManager,
      } = await loadFixture(deployHyperStaking);

      const bigFee = parseEther("0.31"); // 31%
      const newFee = parseEther("0.1"); // 10%

      await expect(tier1.setRevenueFee(reserveStrategy, newFee))
        .to.be.reverted;

      await expect(tier1.connect(strategyVaultManager).setRevenueFee(reserveStrategy, bigFee))
        .to.be.revertedWithCustomError(tier1, "InvalidRevenueFeeValue");

      // OK
      await expect(tier1.connect(strategyVaultManager).setRevenueFee(reserveStrategy, newFee));
    });

    it("revenue fee value should be distracted when withdraw his stake", async function () {
      const { staking, tier1, reserveStrategy, alice, strategyVaultManager } = await loadFixture(deployHyperStaking);
      const gasCosts = new TxCostTracker();

      const revenueFee = parseEther("0.1"); // 10%
      await tier1.connect(strategyVaultManager).setRevenueFee(reserveStrategy, revenueFee);

      const price1 = parseEther("2");
      const price2 = parseEther("2.5");
      const stakeAmount = parseEther("3.0");

      const aliceBalanceBefore = await ethers.provider.getBalance(alice);

      await reserveStrategy.setAssetPrice(price1);

      await gasCosts.includeTx(
        await staking.connect(alice).stakeDeposit(reserveStrategy, stakeAmount, alice, { value: stakeAmount }),
      );

      await reserveStrategy.setAssetPrice(price2);
      const revenue = stakeAmount * price2 / price1 - stakeAmount;

      await gasCosts.includeTx(
        await staking.connect(alice).stakeWithdraw(reserveStrategy, stakeAmount, alice),
      );

      const expectedFee = revenueFee * revenue / parseEther("1");

      // alice balance after
      const expectedAliceBalance = aliceBalanceBefore + revenue - expectedFee - gasCosts.getTotalCosts();
      expect(await ethers.provider.getBalance(alice)).to.equal(expectedAliceBalance);
    });

    describe("Errors", function () {
      it("OnlyStrategyVaultManager", async function () {
        const { vaultFactory, reserveStrategy, alice, defaultRevenueFee } = await loadFixture(deployHyperStaking);

        await expect(vaultFactory.addStrategy(
          reserveStrategy,
          "vault3",
          "V3",
          defaultRevenueFee,
        ))
          .to.be.reverted;

        await expect(vaultFactory.connect(alice).addStrategy(
          reserveStrategy,
          "vault4",
          "V4",
          defaultRevenueFee,
        ))
          // hardhat unfortunately does not recognize custom errors from child contracts
          // .to.be.revertedWithCustomError(vaultFactory, "OnlyStrategyVaultManager");
          .to.be.reverted;
      });

      it("VaultDoesNotExist", async function () {
        const { staking, owner } = await loadFixture(deployHyperStaking);

        const badStrategy = "0x36fD7e46150d3C0Be5741b0fc8b0b2af4a0D4Dc5";

        await expect(staking.stakeDeposit(badStrategy, 1, owner, { value: 1 }))
          .to.be.revertedWithCustomError(staking, "VaultDoesNotExist")
          .withArgs(badStrategy);
      });

      it("VaultAlreadyExist", async function () {
        const {
          vaultFactory, strategyVaultManager, reserveStrategy, defaultRevenueFee,
        } = await loadFixture(deployHyperStaking);

        await expect(vaultFactory.connect(strategyVaultManager).addStrategy(
          reserveStrategy,
          "vault5",
          "V5",
          defaultRevenueFee,
        ))
          .to.be.revertedWithCustomError(vaultFactory, "VaultAlreadyExist");
      });

      it("Vault external functions not be accessible without staking", async function () {
        const { tier1, reserveStrategy, alice } = await loadFixture(deployHyperStaking);

        await expect(tier1.joinTier1(reserveStrategy, alice, 1000))
          .to.be.reverted;

        await expect(tier1.leaveTier1(reserveStrategy, alice, 1000))
          .to.be.reverted;
      });
    });
  });

  describe("Dinero Strategy", function () {
    it("staking deposit to dinero strategy should aquire apxEth", async function () {
      const { staking, vaultFactory, tier1, autoPxEth, dineroStrategy, owner } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("8");
      const apxEthPrice = parseEther("1");

      const expectedFee = 0n;
      const expectedAsset = stakeAmount - expectedFee;
      const expectedShares = autoPxEth.convertToShares(expectedAsset);

      // event
      await expect(staking.stakeDeposit(dineroStrategy, stakeAmount, owner, { value: stakeAmount }))
        .to.emit(dineroStrategy, "Allocate")
        .withArgs(
          owner,
          expectedAsset,
          expectedShares,
        );

      // Strategy
      const stakeCurrency = await dineroStrategy.stakeCurrency() as CurrencyStruct;
      expect(stakeCurrency.token).to.equal(shared.nativeTokenAddress);
      expect(await dineroStrategy.revenueAsset()).to.equal(autoPxEth);

      // Vault
      expect((await vaultFactory.vaultInfo(dineroStrategy)).stakeCurrency).to.deep.equal([shared.nativeTokenAddress]);
      expect((await vaultFactory.vaultInfo(dineroStrategy)).strategy).to.equal(dineroStrategy);
      expect((await vaultFactory.vaultInfo(dineroStrategy)).asset).to.equal(autoPxEth);

      // Tier1
      expect((await tier1.userTier1Info(dineroStrategy, owner)).stake).to.equal(stakeAmount);

      expect((await tier1.vaultTier1Info(dineroStrategy)).assetAllocation).to.equal(stakeAmount * apxEthPrice / parseEther("1"));
      expect((await tier1.vaultTier1Info(dineroStrategy)).totalStake).to.equal(stakeAmount);

      // apxETH balance
      expect(await autoPxEth.balanceOf(vaultFactory)).to.equal(stakeAmount * apxEthPrice / parseEther("1"));
    });

    it("unstaking from to dinero strategy should exchange apxEth back to eth", async function () {
      const { staking, vaultFactory, tier1, autoPxEth, dineroStrategy, owner } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("3");
      const apxEthPrice = parseEther("1");

      await staking.stakeDeposit(dineroStrategy, stakeAmount, owner, { value: stakeAmount });

      await expect(staking.stakeWithdraw(dineroStrategy, stakeAmount, owner))
        .to.emit(dineroStrategy, "Exit")
        .withArgs(owner, stakeAmount * apxEthPrice / parseEther("1"), anyValue);

      expect((await tier1.userTier1Info(dineroStrategy, owner)).stake).to.equal(0);
      expect((await vaultFactory.vaultInfo(dineroStrategy)).asset).to.equal(autoPxEth);

      expect((await tier1.vaultTier1Info(dineroStrategy)).assetAllocation).to.equal(0);
      expect((await tier1.vaultTier1Info(dineroStrategy)).totalStake).to.equal(0);

      expect(await autoPxEth.balanceOf(vaultFactory)).to.equal(0);
    });

    describe("Pirex Mock", function () {
      it("it should be possible to deposit ETH and get pxETH", async function () {
        const [owner] = await ethers.getSigners();
        const { pxEth, pirexEth } = await loadFixture(getMockedPirex);

        await pirexEth.deposit(owner, false, { value: parseEther("1") });

        expect(await pxEth.balanceOf(owner)).to.be.greaterThan(0);
      });

      it("it should be possible to deposit ETH and auto-compund it with apxEth", async function () {
        const [owner] = await ethers.getSigners();
        const { pxEth, pirexEth, autoPxEth } = await loadFixture(getMockedPirex);

        await pirexEth.deposit(owner, true, { value: parseEther("5") });

        expect(await pxEth.balanceOf(owner)).to.equal(0);
        expect(await autoPxEth.balanceOf(owner)).to.be.greaterThan(0);
      });

      it("it should be possible to instant Redeem apxEth back to ETH", async function () {
        const [owner, alice] = await ethers.getSigners();
        const { pxEth, pirexEth, autoPxEth } = await loadFixture(getMockedPirex);

        const initialDeposit = parseEther("1");
        await pirexEth.deposit(owner, true, { value: initialDeposit });

        const totalAssets = await autoPxEth.totalAssets();
        await autoPxEth.withdraw(totalAssets / 2n, owner, owner);

        await expect(pirexEth.instantRedeemWithPxEth(initialDeposit / 2n, alice))
          .to.changeEtherBalances(
            [pirexEth, alice],
            [-initialDeposit / 2n, initialDeposit / 2n],
          );

        expect(await pxEth.balanceOf(owner)).to.equal(0);
      });
    });
  });
});
