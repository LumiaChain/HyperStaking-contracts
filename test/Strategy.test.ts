import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, ignition } from "hardhat";
import { parseEther } from "ethers";

import DineroStrategyModule from "../ignition/modules/DineroStrategy";
import PirexMockModule from "../ignition/modules/test/PirexMock";

import * as shared from "./shared";
// import TxCostTracker from "./txCostTracker";
import { PirexEth } from "../typechain-types";
import { CurrencyStruct } from "../typechain-types/contracts/hyperstaking/facets/HyperFactoryFacet";

async function getMockedPirex() {
  const [, , rewardRecipient] = await ethers.getSigners();
  const { pxEth, upxEth, pirexEth, autoPxEth } = await ignition.deploy(PirexMockModule);

  // increase rewards buffer
  await (pirexEth.connect(rewardRecipient) as PirexEth).harvest(await ethers.provider.getBlockNumber(), { value: parseEther("100") });

  return { pxEth, upxEth, pirexEth, autoPxEth };
}

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testWstETH = await shared.deloyTestERC20("Test Wrapped Liquid Staked ETH", "tWstETH");
  const erc4626Vault = await shared.deloyTestERC4626Vault(testWstETH);

  // --------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Apply Strategies --------------------

  // strategy asset price to eth 2:1
  const reserveAssetPrice = parseEther("2");

  const reserveStrategy = await shared.createReserveStrategy(
    hyperStaking.diamond, shared.nativeTokenAddress, await testWstETH.getAddress(), reserveAssetPrice,
  );

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    reserveStrategy,
    "eth reserve vault1",
    "rETH1",
  );

  const { pxEth, upxEth, pirexEth, autoPxEth } = await loadFixture(getMockedPirex);
  const { dineroStrategy } = await ignition.deploy(DineroStrategyModule, {
    parameters: {
      DineroStrategyModule: {
        diamond: await hyperStaking.diamond.getAddress(),
        pxEth: await pxEth.getAddress(),
        pirexEth: await pirexEth.getAddress(),
        autoPxEth: await autoPxEth.getAddress(),
      },
    },
  });

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    dineroStrategy,
    "eth vault2",
    "dETH2",
  );

  // ----------------------------------------

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    pxEth, upxEth, pirexEth, autoPxEth, // pirex mock
    testWstETH, reserveStrategy, dineroStrategy, // test contracts
    reserveAssetPrice, // values
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

describe("Strategy", function () {
  describe("ReserveStrategy", function () {
    it("check state after allocation", async function () {
      const { hyperStaking, testWstETH, reserveStrategy, reserveAssetPrice, signers } = await loadFixture(deployHyperStaking);
      const { deposit, hyperFactory, stakeVault } = hyperStaking;
      const { owner, alice } = signers;

      const ownerAmount = parseEther("2");
      const aliceAmount = parseEther("8");

      expect(await testWstETH.balanceOf(hyperFactory)).to.equal(0);
      expect(await reserveStrategy.assetPrice()).to.equal(reserveAssetPrice);
      expect(await reserveStrategy.previewAllocation(ownerAmount)).to.equal(ownerAmount * parseEther("1") / reserveAssetPrice);

      // event
      await expect(deposit.stakeDeposit(reserveStrategy, ownerAmount, owner, { value: ownerAmount }))
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(owner, ownerAmount, ownerAmount * parseEther("1") / reserveAssetPrice);

      // TODO: after moving vault to lumia
      // expect(await testWstETH.balanceOf(hyperFactory)).to.equal(ownerAmount * parseEther("1") / reserveAssetPrice);

      // event
      await expect(deposit.stakeDeposit(reserveStrategy, aliceAmount, alice, { value: aliceAmount }))
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(alice, aliceAmount, aliceAmount * parseEther("1") / reserveAssetPrice);

      // VaultInfo
      expect((await hyperFactory.vaultInfo(reserveStrategy)).stakeCurrency).to.deep.equal([shared.nativeTokenAddress]);
      expect((await hyperFactory.vaultInfo(reserveStrategy)).strategy).to.equal(reserveStrategy);
      expect((await hyperFactory.vaultInfo(reserveStrategy)).asset).to.equal(testWstETH);

      // StakeInfo
      expect((await stakeVault.stakeInfo(reserveStrategy)).stakeBridged).to.equal(ownerAmount + aliceAmount);
      expect((await stakeVault.stakeInfo(reserveStrategy)).totalStake).to.equal(ownerAmount + aliceAmount);

      // TODO: ??
      expect((await stakeVault.stakeInfo(reserveStrategy)).assetAllocation).to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);

      // TODO: after moving vault to lumia
      // expect(await testWstETH.balanceOf(hyperFactory)).to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);
    });

    it("there should be a possibility of emergency withdraw", async function () {
      const { reserveStrategy, signers } = await loadFixture(deployHyperStaking);
      const { owner, alice, strategyManager } = signers;

      // send eth to the strategy
      const accidentAmount = parseEther("4.0");
      await owner.sendTransaction({
        to: reserveStrategy,
        value: accidentAmount,
      });

      await expect(reserveStrategy.emergencyWithdrawal(shared.nativeCurrency(), accidentAmount, alice))
        .to.be.revertedWithCustomError(reserveStrategy, "NotStrategyManager");

      await expect(reserveStrategy.connect(strategyManager).emergencyWithdrawal(shared.nativeCurrency(), accidentAmount, alice))
        .to.changeEtherBalances(
          [reserveStrategy, alice],
          [-accidentAmount, accidentAmount],
        );
    });

    describe("Errors", function () {
      it("NotLumiaDimaond", async function () {
        const { reserveStrategy, signers } = await loadFixture(deployHyperStaking);
        const { alice } = signers;

        await expect(reserveStrategy.allocate(parseEther("1"), alice))
          .to.be.revertedWithCustomError(reserveStrategy, "NotLumiaDiamond");

        await expect(reserveStrategy.exit(parseEther("1"), alice))
          .to.be.revertedWithCustomError(reserveStrategy, "NotLumiaDiamond");
      });

      it("NotStrategyManager", async function () {
        const { reserveStrategy, signers } = await loadFixture(deployHyperStaking);
        const { alice } = signers;

        await expect(reserveStrategy.connect(alice).setAssetPrice(parseEther("10")))
          .to.be.revertedWithCustomError(reserveStrategy, "NotStrategyManager");
      });

      it("OnlyVaultManager", async function () {
        const { hyperStaking, reserveStrategy, signers } = await loadFixture(deployHyperStaking);
        const { hyperFactory } = hyperStaking;
        const { alice } = signers;

        await expect(hyperFactory.addStrategy(
          reserveStrategy,
          "vault3",
          "V3",
        ))
          .to.be.reverted;

        await expect(hyperFactory.connect(alice).addStrategy(
          reserveStrategy,
          "vault4",
          "V4",
        ))
          // hardhat unfortunately does not recognize custom errors from child contracts
          // .to.be.revertedWithCustomError(hyperFactory, "OnlyVaultManager");
          .to.be.reverted;
      });

      it("VaultDoesNotExist", async function () {
        const { hyperStaking, signers } = await loadFixture(deployHyperStaking);
        const { deposit } = hyperStaking;
        const { owner } = signers;

        const badStrategy = "0x36fD7e46150d3C0Be5741b0fc8b0b2af4a0D4Dc5";

        await expect(deposit.stakeDeposit(badStrategy, 1, owner, { value: 1 }))
          .to.be.revertedWithCustomError(deposit, "VaultDoesNotExist")
          .withArgs(badStrategy);
      });

      it("VaultAlreadyExist", async function () {
        const { hyperStaking, reserveStrategy, signers } = await loadFixture(deployHyperStaking);
        const { hyperFactory } = hyperStaking;
        const { vaultManager } = signers;

        await expect(hyperFactory.connect(vaultManager).addStrategy(
          reserveStrategy,
          "vault5",
          "V5",
        ))
          .to.be.revertedWithCustomError(hyperFactory, "VaultAlreadyExist");
      });

      it("Vault external functions not be accessible outside deposit", async function () {
        const { hyperStaking, reserveStrategy, signers } = await loadFixture(deployHyperStaking);
        const { stakeVault } = hyperStaking;
        const { alice } = signers;

        await expect(stakeVault.join(reserveStrategy, alice, 1000))
          .to.be.reverted;

        await expect(stakeVault.leave(reserveStrategy, alice, 1000))
          .to.be.reverted;
      });
    });
  });

  describe("Dinero Strategy", function () {
    it("staking deposit to dinero strategy should aquire apxEth", async function () {
      const { hyperStaking, autoPxEth, dineroStrategy, signers } = await loadFixture(deployHyperStaking);
      const { deposit, hyperFactory, stakeVault } = hyperStaking;
      const { owner } = signers;

      const stakeAmount = parseEther("8");
      const apxEthPrice = parseEther("1");

      const expectedFee = 0n;
      const expectedAsset = stakeAmount - expectedFee;
      const expectedShares = autoPxEth.convertToShares(expectedAsset);

      // event
      await expect(deposit.stakeDeposit(dineroStrategy, stakeAmount, owner, { value: stakeAmount }))
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
      expect((await hyperFactory.vaultInfo(dineroStrategy)).stakeCurrency).to.deep.equal([shared.nativeTokenAddress]);
      expect((await hyperFactory.vaultInfo(dineroStrategy)).strategy).to.equal(dineroStrategy);
      expect((await hyperFactory.vaultInfo(dineroStrategy)).asset).to.equal(autoPxEth);

      // StakeInfo
      expect((await stakeVault.stakeInfo(dineroStrategy)).totalStake).to.equal(stakeAmount);
      expect((await stakeVault.stakeInfo(dineroStrategy)).assetAllocation).to.equal(stakeAmount * apxEthPrice / parseEther("1"));

      // apxETH balance
      // TODO: after moving vault to lumia
      // expect(await autoPxEth.balanceOf(hyperFactory)).to.equal(stakeAmount * apxEthPrice / parseEther("1"));
    });

    // TODO: when redeem is implemented
    // it("unstaking from to dinero strategy should exchange apxEth back to eth", async function () {
    //   const { hyperStaking, autoPxEth, dineroStrategy, signers } = await loadFixture(deployHyperStaking);
    //   const { deposit, hyperFactory, stakeVault } = hyperStaking;
    //   const { owner } = signers;
    //
    //   const stakeAmount = parseEther("3");
    //   const apxEthPrice = parseEther("1");
    //
    //   await deposit.stakeDeposit(dineroStrategy, stakeAmount, owner, { value: stakeAmount });
    //
    //   await expect(deposit.stakeWithdrawTier1(dineroStrategy, stakeAmount, owner))
    //     .to.emit(dineroStrategy, "Exit")
    //     .withArgs(owner, stakeAmount * apxEthPrice / parseEther("1"), anyValue);
    //
    //   expect((await hyperFactory.vaultInfo(dineroStrategy)).asset).to.equal(autoPxEth);
    //
    //   expect((await stakeVault.stakeInfo(dineroStrategy)).totalStake).to.equal(0);
    //   expect((await stakeVault.stakeInfo(dineroStrategy)).assetAllocation).to.equal(0);
    //
    //   expect(await autoPxEth.balanceOf(hyperFactory)).to.equal(0);
    // });

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
