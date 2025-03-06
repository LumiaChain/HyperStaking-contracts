import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, ignition } from "hardhat";
import { parseEther } from "ethers";

import DiamondModule from "../ignition/modules/Diamond";
import RevertingContractModule from "../ignition/modules/test/RevertingContract";

import * as shared from "./shared";

describe("Staking", function () {
  async function deployDiamond() {
    const [owner, alice] = await ethers.getSigners();
    const { diamond } = await ignition.deploy(DiamondModule);

    const ownershipFacet = await ethers.getContractAt("OwnershipFacet", diamond);

    return { diamond, ownershipFacet, owner, alice };
  }

  async function deployHyperStaking() {
    const [owner, stakingManager, vaultManager, alice, bob] = await ethers.getSigners();

    // -------------------- Deploy Tokens --------------------

    const testERC20 = await shared.deloyTestERC20("Test ERC20 Token", "tERC20");
    const testWstETH = await shared.deloyTestERC20("Test Wrapped Liquid Staked ETH", "tWstETH");
    const erc4626Vault = await shared.deloyTestERC4626Vault(testERC20);

    // -------------------- Hyperstaking Diamond --------------------

    const { diamond, deposit, hyperFactory, tier1 } = await shared.deployTestHyperStaking(0n, erc4626Vault);

    // -------------------- Apply Strategies --------------------

    const defaultRevenueFee = parseEther("0"); // 0% fee

    const reserveStrategy1 = await shared.createReserveStrategy(
      diamond, shared.nativeTokenAddress, await testWstETH.getAddress(), parseEther("1"),
    );

    const reserveStrategy2 = await shared.createReserveStrategy(
      diamond, await testERC20.getAddress(), await testWstETH.getAddress(), parseEther("2"),
    );

    // strategy with neutral to eth 1:1 asset price
    await hyperFactory.connect(vaultManager).addStrategy(
      reserveStrategy1,
      "eth vault1",
      "vETH1",
      defaultRevenueFee,
    );

    // strategy with erc20 staking token and 2:1 asset price
    await hyperFactory.connect(vaultManager).addStrategy(
      reserveStrategy2,
      "erc20 vault2",
      "vERC2",
      defaultRevenueFee,
    );

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      deposit, hyperFactory, tier1, // diamond facets
      testERC20, testWstETH, reserveStrategy1, reserveStrategy2, // test contracts
      owner, stakingManager, alice, bob, // addresses
    };
    /* eslint-enable object-property-newline */
  }

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
    it("staking can be paused", async function () {
      const { deposit, reserveStrategy1, stakingManager, bob } = await loadFixture(deployHyperStaking);

      // pause
      await expect(deposit.connect(bob).pauseDeposit()).to.be.reverted;
      await expect(deposit.connect(stakingManager).pauseDeposit()).to.not.be.reverted;

      await expect(deposit.stakeDepositTier1(reserveStrategy1, 100, bob, { value: 100 }))
        .to.be.reverted;

      await expect(deposit.connect(bob).stakeWithdrawTier1(reserveStrategy1, 100, bob)).to.be.reverted;

      // unpause
      await expect(deposit.connect(bob).unpauseDeposit()).to.be.reverted;
      await expect(deposit.connect(stakingManager).unpauseDeposit()).to.not.be.reverted;

      await deposit.stakeDepositTier1(reserveStrategy1, 100, bob, { value: 100 });
      await deposit.connect(bob).stakeWithdrawTier1(reserveStrategy1, 100, bob);
    });

    it("should be able to deposit stake", async function () {
      const { deposit, tier1, reserveStrategy1, owner, alice } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("5");
      await expect(deposit.stakeDepositTier1(reserveStrategy1, stakeAmount, owner, { value: stakeAmount }))
        .to.changeEtherBalances(
          [owner, reserveStrategy1],
          [-stakeAmount, stakeAmount],
        );

      // event
      const tier1Id = 1;
      await expect(deposit.stakeDepositTier1(reserveStrategy1, stakeAmount, owner, { value: stakeAmount }))
        .to.emit(deposit, "StakeDeposit")
        .withArgs(owner, owner, reserveStrategy1, stakeAmount, tier1Id);

      const stakeAmountForAlice = parseEther("11");
      await expect(deposit.connect(alice).stakeDepositTier1(
        reserveStrategy1, stakeAmountForAlice, alice, { value: stakeAmountForAlice }),
      )
        .to.emit(deposit, "StakeDeposit")
        .withArgs(alice, alice, reserveStrategy1, stakeAmountForAlice, tier1Id);

      // Tier1
      const vaultInfo = await tier1.tier1Info(reserveStrategy1);
      expect(vaultInfo.totalStake).to.equal(stakeAmount * 2n + stakeAmountForAlice);

      // UserInfo
      expect(
        (await tier1.userTier1Info(reserveStrategy1, owner)).stake,
      ).to.equal(stakeAmount * 2n);
      expect(
        (await tier1.userTier1Info(reserveStrategy1, alice)).stake,
      ).to.equal(stakeAmountForAlice);
    });

    it("should be able to withdraw stake", async function () {
      const { deposit, tier1, reserveStrategy1, owner, alice } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("6.4");
      const withdrawAmount = parseEther(".8");

      await deposit.stakeDepositTier1(reserveStrategy1, stakeAmount, owner, { value: stakeAmount });

      await expect(deposit.stakeWithdrawTier1(reserveStrategy1, withdrawAmount, owner))
        .to.changeEtherBalances(
          [owner, reserveStrategy1],
          [withdrawAmount, -withdrawAmount],
        );

      const tier1StakeType = 1;
      await expect(deposit.stakeWithdrawTier1(reserveStrategy1, withdrawAmount, owner))
        .to.emit(deposit, "StakeWithdraw")
        .withArgs(owner, owner, reserveStrategy1, withdrawAmount, anyValue, tier1StakeType);

      const precisionError = 4n; // 4wei
      await expect(deposit.stakeWithdrawTier1(reserveStrategy1, withdrawAmount, alice))
        .to.changeEtherBalances(
          [alice, reserveStrategy1],
          [withdrawAmount - precisionError, -withdrawAmount + precisionError],
        );

      // Tier1
      const vaultInfo = await tier1.tier1Info(reserveStrategy1);
      expect(vaultInfo.totalStake).to.equal(stakeAmount - 3n * withdrawAmount);

      // UserInfo
      expect(
        (await tier1.userTier1Info(reserveStrategy1, owner)).stake,
      ).to.equal(stakeAmount - 3n * withdrawAmount);
      expect(
        (await tier1.userTier1Info(reserveStrategy1, alice)).stake,
      ).to.equal(0);
    });

    it("it should be possible to stake and withdraw with erc20", async function () {
      const { deposit, tier1, testERC20, reserveStrategy2, owner, alice } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("7.8");
      const withdrawAmount = parseEther("1.4");

      await testERC20.approve(deposit, stakeAmount);
      await deposit.stakeDepositTier1(reserveStrategy2, stakeAmount, owner);

      const precisionError = 2n; // 2wei
      await expect(deposit.stakeWithdrawTier1(reserveStrategy2, withdrawAmount, owner))
        .to.changeTokenBalances(testERC20,
          [owner, reserveStrategy2],
          [withdrawAmount - precisionError, -withdrawAmount + precisionError],
        );

      const tier1StakeType = 1;
      await expect(deposit.stakeWithdrawTier1(reserveStrategy2, withdrawAmount, owner))
        .to.emit(deposit, "StakeWithdraw")
        .withArgs(owner, owner, reserveStrategy2, withdrawAmount, withdrawAmount, tier1StakeType);

      await expect(deposit.stakeWithdrawTier1(reserveStrategy2, withdrawAmount, alice))
        .to.changeTokenBalances(testERC20,
          [alice, reserveStrategy2],
          [withdrawAmount, -withdrawAmount],
        );

      // Tier1
      const vaultInfo = await tier1.tier1Info(reserveStrategy2);
      expect(vaultInfo.totalStake).to.equal(stakeAmount - 3n * withdrawAmount);

      // UserInfo
      expect(
        (await tier1.userTier1Info(reserveStrategy2, owner)).stake,
      ).to.equal(stakeAmount - 3n * withdrawAmount);
      expect(
        (await tier1.userTier1Info(reserveStrategy2, alice)).stake,
      ).to.equal(0);
    });

    describe("CurrencyHandler Errors", function () {
      it("Invalid deposit value", async function () {
        const { deposit, reserveStrategy1, owner } = await loadFixture(deployHyperStaking);

        const stakeAmount = parseEther("1");
        const value = parseEther("0.99");

        await expect(deposit.stakeDepositTier1(reserveStrategy1, stakeAmount, owner, { value }))
          .to.be.revertedWith("Insufficient native value");
      });

      it("Transfer call failed", async function () {
        const { deposit, reserveStrategy1, owner } = await loadFixture(deployHyperStaking);

        // test contract which reverts on payable call
        const { revertingContract } = await ignition.deploy(RevertingContractModule);

        const stakeAmount = parseEther("1");

        await deposit.stakeDepositTier1(reserveStrategy1, stakeAmount, owner, { value: stakeAmount });
        await expect(deposit.stakeWithdrawTier1(reserveStrategy1, stakeAmount, revertingContract))
          .to.be.revertedWith("Transfer call failed");
      });
    });
  });
});
