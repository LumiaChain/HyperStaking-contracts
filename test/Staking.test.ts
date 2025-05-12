import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers, ignition } from "hardhat";
import { parseEther } from "ethers";

import DiamondModule from "../ignition/modules/Diamond";
import RevertingContractModule from "../ignition/modules/test/RevertingContract";

import * as shared from "./shared";

async function deployDiamond() {
  const [owner, alice] = await ethers.getSigners();
  const { diamond } = await ignition.deploy(DiamondModule);

  const ownershipFacet = await ethers.getContractAt("OwnershipFacet", diamond);

  return { diamond, ownershipFacet, owner, alice };
}

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testERC20 = await shared.deloyTestERC20("Test ERC20 Token", "tERC20");
  const testWstETH = await shared.deloyTestERC20("Test Wrapped Liquid Staked ETH", "tWstETH");
  const erc4626Vault = await shared.deloyTestERC4626Vault(testERC20);

  await testERC20.mint(signers.alice, parseEther("1000"));
  await testERC20.mint(signers.bob, parseEther("1000"));

  // -------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Apply Strategies --------------------

  const reserveStrategy1 = await shared.createReserveStrategy(
    hyperStaking.diamond, shared.nativeTokenAddress, await testWstETH.getAddress(), parseEther("1"),
  );

  const reserveStrategy2 = await shared.createReserveStrategy(
    hyperStaking.diamond, await testERC20.getAddress(), await testWstETH.getAddress(), parseEther("2"),
  );

  // strategy with neutral to eth 1:1 asset price
  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    reserveStrategy1,
    "eth vault1",
    "vETH1",
  );

  // strategy with erc20 staking token and 2:1 asset price
  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    reserveStrategy2,
    "erc20 vault2",
    "vERC2",
  );

  // -------------------- Hyperlane Handler --------------------

  const lumiaTokens1 = await shared.getDerivedTokens(
    hyperStaking.hyperlaneHandler,
    await reserveStrategy1.getAddress(),
  );

  const lumiaTokens2 = await shared.getDerivedTokens(
    hyperStaking.hyperlaneHandler,
    await reserveStrategy2.getAddress(),
  );

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    testERC20, testWstETH, reserveStrategy1, reserveStrategy2, lumiaTokens1, lumiaTokens2, // test contracts
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

describe("Staking", function () {
  describe("Diamond Ownership", function () {
    it("should set the right owner", async function () {
      const { ownershipFacet, owner } = await loadFixture(deployDiamond);

      expect(await ownershipFacet.owner()).to.equal(owner);
    });

    it("it should be able to transfer ownership", async function () {
      const { ownershipFacet, alice } = await loadFixture(deployDiamond);

      await ownershipFacet.transferOwnership(alice);
      expect(await ownershipFacet.owner()).to.equal(alice);
    });
  });

  describe("Staking", function () {
    it("deposit staking can be paused", async function () {
      const { hyperStaking, reserveStrategy1, signers } = await loadFixture(deployHyperStaking);
      const { deposit, hyperFactory } = hyperStaking;

      const { stakingManager, vaultManager, bob } = signers;

      // pause
      await expect(deposit.connect(bob).pauseDeposit()).to.be.reverted;
      await expect(deposit.connect(stakingManager).pauseDeposit()).to.not.be.reverted;

      await expect(deposit.stakeDeposit(reserveStrategy1, bob, 100, { value: 100 }))
        .to.be.reverted;

      // unpause
      await expect(deposit.connect(bob).unpauseDeposit()).to.be.reverted;
      await expect(deposit.connect(stakingManager).unpauseDeposit()).to.not.be.reverted;

      await deposit.stakeDeposit(reserveStrategy1, bob, 100, { value: 100 });

      // by individual strategy
      await expect(hyperFactory.setStrategyEnabled(reserveStrategy1, false)).to.be.reverted;
      await hyperFactory.connect(vaultManager).setStrategyEnabled(reserveStrategy1, false); // OK

      await expect(deposit.stakeDeposit(reserveStrategy1, bob, 100, { value: 100 }))
        .to.be.reverted;

      await hyperFactory.connect(vaultManager).setStrategyEnabled(reserveStrategy1, true); // enable

      await deposit.stakeDeposit(reserveStrategy1, bob, 100, { value: 100 }); // OK
    });

    it("should be able to deposit stake", async function () {
      const { hyperStaking, reserveStrategy1, signers } = await loadFixture(deployHyperStaking);
      const { deposit, allocation } = hyperStaking;
      const { owner, alice } = signers;

      await expect(deposit.stakeDeposit(reserveStrategy1, owner, 0))
        .to.be.revertedWithCustomError(deposit, "ZeroStake");

      const stakeAmount = parseEther("5");
      await expect(deposit.stakeDeposit(reserveStrategy1, owner, stakeAmount, { value: stakeAmount }))
        .to.changeEtherBalances(
          [owner, reserveStrategy1],
          [-stakeAmount, stakeAmount],
        );

      // event
      const depositType = 1;
      await expect(deposit.stakeDeposit(reserveStrategy1, owner, stakeAmount, { value: stakeAmount }))
        .to.emit(deposit, "StakeDeposit")
        .withArgs(owner, owner, reserveStrategy1, stakeAmount, depositType);

      const stakeAmountForAlice = parseEther("11");
      await expect(deposit.connect(alice).stakeDeposit(
        reserveStrategy1, alice, stakeAmountForAlice, { value: stakeAmountForAlice }),
      )
        .to.emit(deposit, "StakeDeposit")
        .withArgs(alice, alice, reserveStrategy1, stakeAmountForAlice, depositType);

      // Allocation
      const vaultInfo = await allocation.stakeInfo(reserveStrategy1);
      expect(vaultInfo.totalStake).to.equal(stakeAmount * 2n + stakeAmountForAlice);
      expect(vaultInfo.totalAllocation).to.equal(stakeAmount * 2n + stakeAmountForAlice);
    });

    it("should be able to withdraw stake", async function () {
      const { hyperStaking, reserveStrategy1, lumiaTokens1, signers } = await loadFixture(deployHyperStaking);
      const { deposit, allocation, realAssets } = hyperStaking;
      const { owner, alice } = signers;

      const stakeAmount = parseEther("6.4");
      const withdrawAmount = parseEther("0.8");

      await deposit.stakeDeposit(reserveStrategy1, owner, stakeAmount, { value: stakeAmount });

      await lumiaTokens1.vaultShares.approve(realAssets, withdrawAmount);
      await expect(realAssets.redeem(reserveStrategy1, owner, owner, withdrawAmount))
        .to.changeEtherBalances(
          [owner, reserveStrategy1],
          [withdrawAmount, -withdrawAmount],
        );

      const depositType = 1;
      await lumiaTokens1.vaultShares.approve(realAssets, withdrawAmount);
      await expect(realAssets.redeem(reserveStrategy1, owner, owner, withdrawAmount))
        .to.emit(deposit, "StakeWithdraw")
        .withArgs(owner, reserveStrategy1, withdrawAmount, depositType);

      // wihdraw to another address
      await lumiaTokens1.vaultShares.approve(realAssets, withdrawAmount);
      await expect(realAssets.redeem(reserveStrategy1, owner, alice, withdrawAmount))
        .to.changeEtherBalances(
          [alice, reserveStrategy1],
          [withdrawAmount, -withdrawAmount],
        );

      // Allocation
      const vaultInfo = await allocation.stakeInfo(reserveStrategy1);
      expect(vaultInfo.totalStake).to.equal(stakeAmount - 3n * withdrawAmount);
      expect(vaultInfo.totalAllocation).to.equal(stakeAmount - 3n * withdrawAmount);

      const directVaultInfo = await deposit.directStakeInfo(reserveStrategy1);
      expect(directVaultInfo.totalStake).to.equal(0);
    });

    it("it should be possible to stake and withdraw with erc20", async function () {
      const { hyperStaking, testERC20, reserveStrategy2, signers, lumiaTokens2 } = await loadFixture(deployHyperStaking);
      const { deposit, allocation, realAssets } = hyperStaking;
      const { owner, alice } = signers;

      const stakeAmount = parseEther("7.8");
      const withdrawAmount = parseEther("1.4");

      await testERC20.approve(deposit, stakeAmount);
      await deposit.stakeDeposit(reserveStrategy2, owner, stakeAmount);

      await lumiaTokens2.vaultShares.approve(realAssets, withdrawAmount);
      await expect(realAssets.redeem(reserveStrategy2, owner, owner, withdrawAmount))
        .to.changeTokenBalances(testERC20,
          [owner, reserveStrategy2],
          [withdrawAmount, -withdrawAmount],
        );

      const depositType = 1;
      await lumiaTokens2.vaultShares.approve(realAssets, withdrawAmount);
      await expect(realAssets.redeem(reserveStrategy2, owner, owner, withdrawAmount))
        .to.emit(deposit, "StakeWithdraw")
        .withArgs(owner, reserveStrategy2, withdrawAmount, depositType);

      // wihdraw to another address
      await lumiaTokens2.vaultShares.approve(realAssets, withdrawAmount);
      await expect(realAssets.redeem(reserveStrategy2, owner, alice, withdrawAmount))
        .to.changeTokenBalances(testERC20,
          [alice, reserveStrategy2],
          [withdrawAmount, -withdrawAmount],
        );

      // Allocation
      const vaultInfo = await allocation.stakeInfo(reserveStrategy2);
      expect(vaultInfo.totalStake).to.equal(stakeAmount - 3n * withdrawAmount);
      expect(vaultInfo.totalAllocation).to.equal((stakeAmount - 3n * withdrawAmount) / 2n); // 2 - price of the asset

      // UserInfo
      expect(await lumiaTokens2.vaultShares.balanceOf(owner)).to.equal(stakeAmount - 3n * withdrawAmount);
      expect(await lumiaTokens2.vaultShares.balanceOf(alice)).to.equal(0);

      const directVaultInfo = await deposit.directStakeInfo(reserveStrategy2);
      expect(directVaultInfo.totalStake).to.equal(0);
    });

    describe("Allocation Report", function () {
      it("report in case of zero feeRate", async function () {
        const {
          hyperStaking, reserveStrategy2, testERC20, lumiaTokens2, signers,
        } = await loadFixture(deployHyperStaking);
        const { deposit, hyperFactory, allocation, realAssets } = hyperStaking;
        const { vaultManager, strategyManager, alice, bob } = signers;

        const amount = parseEther("10");

        await testERC20.connect(alice).approve(deposit, amount);
        await deposit.connect(alice).stakeDeposit(reserveStrategy2, alice, amount);

        // lpToken on the Lumia chain side
        const rwaBalance = await lumiaTokens2.vaultShares.balanceOf(alice);
        expect(rwaBalance).to.be.eq(amount);

        // simulate yield generation, double strategy asset price
        const assetPrice = await reserveStrategy2.assetPrice();
        await reserveStrategy2.connect(strategyManager).setAssetPrice(assetPrice * 2n); // double the assets

        await lumiaTokens2.vaultShares.connect(alice).approve(realAssets, rwaBalance);
        await expect(realAssets.connect(alice).redeem(reserveStrategy2, alice, alice, rwaBalance))
          .to.changeTokenBalances(testERC20,
            [alice, reserveStrategy2], [amount, -amount]);

        // vault has double the assets, so the revenue is the same as the amount
        const expectedRevenue = amount;
        expect(await allocation.checkRevenue(reserveStrategy2)).to.be.eq(expectedRevenue);

        await expect(allocation.connect(vaultManager).report(reserveStrategy2))
          .to.be.revertedWithCustomError(allocation, "FeeRecipientUnset");

        expect((await hyperFactory.vaultInfo(reserveStrategy2)).feeRate).to.be.eq(0);

        const feeRecipient = bob;
        await allocation.connect(vaultManager).setFeeRecipient(reserveStrategy2, feeRecipient);

        const reportTx = allocation.connect(vaultManager).report(reserveStrategy2);

        // events
        const feeRate = 0;
        const feeAmount = 0;
        const feeAllocation = 0;
        await expect(reportTx).to.emit(allocation, "StakeCompounded").withArgs(
          reserveStrategy2, feeRecipient, feeRate, feeAmount, feeAllocation, expectedRevenue,
        );

        // balance
        await expect(reportTx).to.changeTokenBalance(lumiaTokens2.principalToken, lumiaTokens2.vaultShares, expectedRevenue);

        expect(await lumiaTokens2.vaultShares.balanceOf(alice)).to.be.eq(0);
      });

      it("revenue and bridge safety margin", async function () {
        const { hyperStaking, reserveStrategy1, lumiaTokens1, signers } = await loadFixture(deployHyperStaking);
        const { deposit, allocation, hyperFactory, realAssets } = hyperStaking;
        const { alice, vaultManager, strategyManager } = signers;

        // safety margin == 0 as default
        expect((await hyperFactory.vaultInfo(reserveStrategy1)).bridgeSafetyMargin).to.be.eq(0);

        const stakeAmount = parseEther("50");

        await deposit.stakeDeposit(reserveStrategy1, alice, stakeAmount, { value: stakeAmount });

        // simulate yield generation, increase asset price
        const assetPrice = await reserveStrategy1.assetPrice();
        await reserveStrategy1.connect(strategyManager).setAssetPrice(assetPrice * 15n / 10n); // 50% increase

        // withdraw half of the assets
        await lumiaTokens1.vaultShares.connect(alice).approve(realAssets, stakeAmount / 2n);
        await realAssets.connect(alice).redeem(reserveStrategy1, alice, alice, stakeAmount / 2n);

        const newBridgeSafetyMargin = parseEther("0.05"); // 5%;
        const expectedRevenue = await allocation.checkRevenue(reserveStrategy1);

        // only vault manager should be able to change the bridge safety margin
        await expect(allocation.setBridgeSafetyMargin(reserveStrategy1, newBridgeSafetyMargin))
          .to.be.reverted;

        // must be grerated than min safety margin
        await expect(allocation.connect(vaultManager).setBridgeSafetyMargin(reserveStrategy1, parseEther("1")))
          .to.be.revertedWithCustomError(allocation, "SafetyMarginTooHigh");

        // OK
        await allocation.connect(vaultManager).setBridgeSafetyMargin(reserveStrategy1, newBridgeSafetyMargin);

        // the safety margin is 5% of the total stake
        const safetyMarginAmount = (await allocation.stakeInfo(reserveStrategy1)).totalStake * newBridgeSafetyMargin / parseEther("1");

        expect(await allocation.checkRevenue(reserveStrategy1)).to.be.eq(expectedRevenue - safetyMarginAmount);
      });

      it("check with non zero protocol fee rate", async function () {
        const { hyperStaking, reserveStrategy1, signers } = await loadFixture(deployHyperStaking);
        const { deposit, allocation } = hyperStaking;
        const { alice, bob, vaultManager, strategyManager } = signers;

        const feeRecipient = bob;
        await allocation.connect(vaultManager).setFeeRecipient(reserveStrategy1, feeRecipient);

        const stakeAmount = parseEther("10");

        await deposit.stakeDeposit(reserveStrategy1, alice, stakeAmount, { value: stakeAmount });

        // simulate yield generation, increase asset price
        let assetPrice = await reserveStrategy1.assetPrice();
        await reserveStrategy1.connect(strategyManager).setAssetPrice(assetPrice * 12n / 10n); // 20% increase

        // set 10% revenue protocol fee
        const feeRate = parseEther("1");
        await allocation.connect(vaultManager).setFeeRate(reserveStrategy1, feeRate);

        let expectedRevenue = await allocation.checkRevenue(reserveStrategy1);
        let expectedFeeAmount = expectedRevenue * feeRate / parseEther("1");
        let expectedFeeAllocation = await reserveStrategy1.previewAllocation(expectedFeeAmount);

        const reportTx1 = await allocation.connect(vaultManager).report(reserveStrategy1);

        await expect(reportTx1).to.emit(allocation, "StakeCompounded").withArgs(
          reserveStrategy1, feeRecipient, feeRate, expectedFeeAmount, expectedFeeAllocation, expectedRevenue - expectedFeeAmount,
        );

        const precisionError = 1n; // 1 wei
        await expect(reportTx1).to.changeEtherBalances(
          [feeRecipient, reserveStrategy1],
          [expectedFeeAmount - precisionError, -expectedFeeAmount + precisionError],
        );

        // after reporting, the revenue is zero
        expect(await allocation.checkRevenue(reserveStrategy1)).to.be.eq(0);

        // --- with safety margin ---

        const newBridgeSafetyMargin = parseEther("0.05"); // 5%;

        // increase the asset price again
        assetPrice = await reserveStrategy1.assetPrice();
        await reserveStrategy1.connect(strategyManager).setAssetPrice(assetPrice * 12n / 10n); // 20% increase

        expectedRevenue = await allocation.checkRevenue(reserveStrategy1);
        await allocation.connect(vaultManager).setBridgeSafetyMargin(reserveStrategy1, newBridgeSafetyMargin);

        // the safety margin is 5% of the total stake
        const safetyMarginAmount = (await allocation.stakeInfo(reserveStrategy1)).totalStake * newBridgeSafetyMargin / parseEther("1");

        expect(await allocation.checkRevenue(reserveStrategy1)).to.be.eq(expectedRevenue - safetyMarginAmount);

        expectedFeeAmount = (expectedRevenue - safetyMarginAmount) * feeRate / parseEther("1");
        expectedFeeAllocation = await reserveStrategy1.previewAllocation(expectedFeeAmount);

        const reportTx2 = await allocation.connect(vaultManager).report(reserveStrategy1);

        await expect(reportTx2).to.emit(allocation, "StakeCompounded").withArgs(
          reserveStrategy1, feeRecipient, feeRate, expectedFeeAmount, expectedFeeAllocation, expectedRevenue - (expectedFeeAmount + safetyMarginAmount),
        );

        await expect(reportTx2).to.changeEtherBalances(
          [feeRecipient, reserveStrategy1],
          [expectedFeeAmount - precisionError, -expectedFeeAmount + precisionError],
        );

        // after reporting, the revenue is zero
        expect(await allocation.checkRevenue(reserveStrategy1)).to.be.eq(precisionError);
      });
    });

    describe("CurrencyHandler Errors", function () {
      it("Invalid deposit value", async function () {
        const { hyperStaking, reserveStrategy1, signers } = await loadFixture(deployHyperStaking);
        const { deposit } = hyperStaking;
        const { owner } = signers;

        const stakeAmount = parseEther("1");
        const value = parseEther("0.99");

        await expect(deposit.stakeDeposit(reserveStrategy1, owner, stakeAmount, { value }))
          .to.be.revertedWith("Insufficient native value");
      });

      it("Withdraw call failed", async function () {
        const { hyperStaking, reserveStrategy1, lumiaTokens1, signers } = await loadFixture(deployHyperStaking);
        const { deposit, realAssets } = hyperStaking;
        const { owner } = signers;

        // test contract which reverts on payable call
        const { revertingContract } = await ignition.deploy(RevertingContractModule);

        const stakeAmount = parseEther("1");

        await deposit.stakeDeposit(reserveStrategy1, owner, stakeAmount, { value: stakeAmount });

        await lumiaTokens1.vaultShares.approve(realAssets, stakeAmount);
        await expect(realAssets.redeem(reserveStrategy1, owner, revertingContract, stakeAmount))
          .to.be.revertedWith("Transfer call failed");
      });
    });
  });
});
