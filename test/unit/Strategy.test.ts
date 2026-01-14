import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers, ignition } from "hardhat";
import { parseEther, ZeroAddress } from "ethers";

import DineroStrategyModule from "../../ignition/modules/DineroStrategy";
import PirexMockModule from "../../ignition/modules/test/PirexMock";

import * as shared from "../shared";
// import TxCostTracker from "../txCostTracker";
import { PirexEth } from "../../typechain-types";
import { CurrencyStruct } from "../../typechain-types/contracts/hyperstaking/facets/HyperFactoryFacet";
import { deployHyperStakingBase } from "../setup";

async function getMockedPirex() {
  const [, , rewardRecipient] = await ethers.getSigners();
  const { pxEth, upxEth, pirexEth, autoPxEth } = await ignition.deploy(PirexMockModule);

  // increase rewards buffer
  await (pirexEth.connect(rewardRecipient) as PirexEth).harvest(await ethers.provider.getBlockNumber(), { value: parseEther("100") });

  return { pxEth, upxEth, pirexEth, autoPxEth };
}

async function deployHyperStaking() {
  const {
    signers, testWstETH, hyperStaking, lumiaDiamond, invariantChecker,
  } = await loadFixture(deployHyperStakingBase);

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

  // -------------------- Setup Checker --------------------

  await invariantChecker.addStrategy(await reserveStrategy.getAddress());
  await invariantChecker.addStrategy(await dineroStrategy.getAddress());
  setGlobalInvariantChecker(invariantChecker);

  // -------------------- Hyperlane Handler --------------------

  const { principalToken, vaultShares } = await shared.getDerivedTokens(
    lumiaDiamond.hyperlaneHandler,
    await dineroStrategy.getAddress(),
  );

  // ----------------------------------------

  /* eslint-disable object-property-newline */
  return {
    signers, // signers
    hyperStaking, lumiaDiamond, // diamonds deployment
    pxEth, upxEth, pirexEth, autoPxEth, // pirex mock
    testWstETH, reserveStrategy, dineroStrategy, principalToken, vaultShares, // test contracts
    reserveAssetPrice, // values
  };
  /* eslint-enable object-property-newline */
}

describe("Strategy", function () {
  describe("UUPS Strategy upgrade", () => {
    it("blocks non-upgrader, allows authorized upgrader", async () => {
      const { reserveStrategy, signers } = await loadFixture(deployHyperStaking);
      const { strategyUpgrader, alice } = signers;

      // check versioning
      expect(await reserveStrategy.implementationVersion()).to.equal("IStrategy 1.1.0");

      const IMPL_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
      const proxyContract = await ethers.getContractAt("UUPSUpgradeable", reserveStrategy);

      // impl V2
      const implFactory = await ethers.getContractFactory("DineroStrategy");
      const implV2 = await implFactory.deploy();
      await implV2.waitForDeployment();

      // non-upgrader cannot upgrade
      await expect(
        reserveStrategy.connect(alice).upgradeToAndCall(implV2.target, "0x"),
      ).to.be.revertedWithCustomError(reserveStrategy, "NotStrategyUpgrader");

      // Authorized upgrade; assert event from the proxy
      await expect(proxyContract.connect(strategyUpgrader).upgradeToAndCall(implV2.target, "0x"))
        .to.emit(proxyContract, "Upgraded")
        .withArgs(await implV2.getAddress());

      // verify the EIP-1967 implementation slot changed
      const implSlot = await ethers.provider.getStorage(proxyContract, IMPL_SLOT);
      expect(ethers.getAddress("0x" + implSlot.slice(26))) // last 20 bytes
        .to.equal(await implV2.getAddress());

      // check versioning again (check if new implementation is working)
      expect(await reserveStrategy.implementationVersion()).to.equal("IStrategy 1.1.0");
    });
  });

  describe("ReserveStrategy", function () {
    afterEach(async () => {
      const c = globalThis.$invChecker;
      if (c) await c.check();
    });

    it("check state after allocation", async function () {
      const { hyperStaking, testWstETH, reserveStrategy, reserveAssetPrice, signers } = await loadFixture(deployHyperStaking);
      const { deposit, hyperFactory, allocation, lockbox } = hyperStaking;
      const { owner, alice } = signers;

      const ownerAmount = parseEther("2");
      const aliceAmount = parseEther("8");

      expect(await testWstETH.balanceOf(hyperFactory)).to.equal(0);
      expect(await reserveStrategy.assetPrice()).to.equal(reserveAssetPrice);
      expect(await reserveStrategy.previewAllocation(ownerAmount)).to.equal(ownerAmount * parseEther("1") / reserveAssetPrice);

      // deposit to owner
      const reqId = 1;
      const readyAt = 0;
      const expectedAllocation = ownerAmount * parseEther("1") / reserveAssetPrice;

      const depositTx = await deposit.deposit(reserveStrategy, owner, ownerAmount, { value: ownerAmount });

      await expect(depositTx)
        .to.emit(reserveStrategy, "AllocationRequested")
        .withArgs(reqId, owner, ownerAmount, readyAt);

      await expect(depositTx)
        .to.emit(reserveStrategy, "AllocationClaimed")
        .withArgs(reqId, lockbox.target, expectedAllocation);

      expect(await testWstETH.balanceOf(hyperFactory)).to.equal(ownerAmount * parseEther("1") / reserveAssetPrice);

      // deposit to alice
      const reqId2 = 2;
      const expectedAllocation2 = aliceAmount * parseEther("1") / reserveAssetPrice;

      const depositTx2 = deposit.deposit(reserveStrategy, alice, aliceAmount, { value: aliceAmount });

      await expect(depositTx2)
        .to.emit(reserveStrategy, "AllocationRequested")
        .withArgs(reqId2, alice, aliceAmount, readyAt);

      await expect(depositTx2)
        .to.emit(reserveStrategy, "AllocationClaimed")
        .withArgs(reqId2, lockbox.target, expectedAllocation2);

      // VaultInfo
      expect((await hyperFactory.vaultInfo(reserveStrategy)).enabled).to.deep.equal(true);
      expect((await hyperFactory.vaultInfo(reserveStrategy)).stakeCurrency).to.deep.equal([shared.nativeTokenAddress]);
      expect((await hyperFactory.vaultInfo(reserveStrategy)).strategy).to.equal(reserveStrategy);
      expect((await hyperFactory.vaultInfo(reserveStrategy)).revenueAsset).to.equal(testWstETH);

      // StakeInfo
      expect((await allocation.stakeInfo(reserveStrategy)).totalStake).to.equal(ownerAmount + aliceAmount);
      expect((await allocation.stakeInfo(reserveStrategy)).totalAllocation).to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);

      expect(await testWstETH.balanceOf(hyperFactory)).to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);
    });

    it("requestInfo & requestInfoBatch reflect queued withdraws", async function () {
      const {
        signers, hyperStaking, lumiaDiamond, reserveStrategy,
      } = await loadFixture(deployHyperStaking);
      const { deposit } = hyperStaking;
      const { realAssets } = lumiaDiamond;
      const { alice } = signers;

      const stakeAmount = parseEther("5");

      await deposit.connect(alice).deposit(reserveStrategy, alice, stakeAmount, { value: stakeAmount });

      const readyAt = 0;
      const id1 = 1; // allocation request

      // single
      const info = await reserveStrategy.requestInfo(id1);
      expect(info.user).to.eq(alice);
      expect(info.isExit).to.eq(false);
      expect(info.amount).to.eq(stakeAmount);
      expect(info.readyAt).to.eq(readyAt);
      expect(info.claimed).to.eq(true);
      expect(info.claimable).to.eq(false);

      // queue withdraw
      const withdraw = parseEther("1");

      const expectedAllocation = await reserveStrategy.previewAllocation(withdraw);

      await realAssets.connect(alice).redeem(reserveStrategy, alice, alice, withdraw);

      const id2 = await shared.getLastClaimId(deposit, reserveStrategy, alice);

      // batch
      const res = await reserveStrategy.requestInfoBatch([id1, id2]);
      expect(res.users[0]).to.eq(alice);
      expect(res.isExits[0]).to.eq(false);
      expect(res.amounts[0]).to.eq(stakeAmount);
      expect(res.readyAts[0]).to.eq(readyAt);
      expect(res.claimedArr[0]).to.eq(true);
      expect(res.claimables[0]).to.eq(false);

      expect(res.users[1]).to.eq(alice);
      expect(res.isExits[1]).to.eq(true);
      expect(res.amounts[1]).to.eq(expectedAllocation);
      expect(res.readyAts[1]).to.eq(readyAt);
      expect(res.claimedArr[1]).to.eq(false);
      expect(res.claimables[1]).to.eq(true);
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

        const testRequestId = 10;
        await expect(reserveStrategy.requestAllocation(testRequestId, parseEther("1"), alice))
          .to.be.revertedWithCustomError(reserveStrategy, "NotLumiaDiamond");

        await expect(reserveStrategy.claimAllocation([testRequestId], alice))
          .to.be.revertedWithCustomError(reserveStrategy, "NotLumiaDiamond");

        await expect(reserveStrategy.requestExit(testRequestId, parseEther("1"), alice))
          .to.be.revertedWithCustomError(reserveStrategy, "NotLumiaDiamond");

        await expect(reserveStrategy.claimExit([testRequestId], alice))
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
        const { signers, hyperStaking } = await loadFixture(deployHyperStaking);
        const { deposit } = hyperStaking;
        const { owner } = signers;

        const badStrategy = "0x36fD7e46150d3C0Be5741b0fc8b0b2af4a0D4Dc5";

        await expect(deposit.deposit(badStrategy, owner, 1, { value: 1 }))
          .to.be.revertedWithCustomError(deposit, "VaultDoesNotExist")
          .withArgs(badStrategy);
      });

      it("ZeroAddress strategy", async function () {
        const { signers, hyperStaking } = await loadFixture(deployHyperStaking);
        const { hyperFactory } = hyperStaking;
        const { vaultManager } = signers;

        const zeroStrategy = ZeroAddress;

        await expect(hyperFactory.connect(vaultManager).addStrategy(
          zeroStrategy,
          "zero vault",
          "v0",
        )).to.be.revertedWithCustomError(shared.errors, "ZeroAddress");
      });

      it("VaultAlreadyExist", async function () {
        const { signers, hyperStaking, reserveStrategy } = await loadFixture(deployHyperStaking);
        const { hyperFactory } = hyperStaking;
        const { vaultManager } = signers;

        await expect(hyperFactory.connect(vaultManager).addStrategy(
          reserveStrategy,
          "vault5",
          "V5",
        )).to.be.revertedWithCustomError(hyperFactory, "VaultAlreadyExist");
      });

      it("Allocation external functions not be accessible outside deposit", async function () {
        const { signers, hyperStaking, reserveStrategy } = await loadFixture(deployHyperStaking);
        const { allocation } = hyperStaking;
        const { alice } = signers;

        await expect(allocation.joinSync(reserveStrategy, alice, 1000))
          .to.be.reverted;

        await expect(allocation.joinAsync(reserveStrategy, alice, 1000))
          .to.be.reverted;

        await expect(allocation.leave(reserveStrategy, alice, 1000))
          .to.be.reverted;
      });
    });

    describe("Refunds", function () {
      it("refunds allocation request (deposit flow) and cleans request storage", async function () {
        const { hyperStaking, reserveStrategy, signers } = await loadFixture(deployHyperStaking);
        const { deposit, allocation } = hyperStaking;
        const { owner, strategyManager } = signers;

        // make allocation async so request is actually pending
        const allocationDelay = 24 * 3600; // 1 day
        await reserveStrategy.connect(strategyManager).setReadyAtOffsets(allocationDelay, 0);

        const stakeAmount = parseEther("2");

        // deposit creates allocation request (not claimed yet)
        const depositTx = await deposit.requestDeposit(reserveStrategy, owner, stakeAmount, { value: stakeAmount });

        const reqId = 1;
        const ts0 = await shared.getCurrentBlockTimestamp();
        const expectedReadyAt = ts0 + allocationDelay;

        await expect(depositTx)
          .to.emit(reserveStrategy, "AllocationRequested")
          .withArgs(reqId, owner, stakeAmount, expectedReadyAt);

        // before readyAt, request should not be claimable
        const infoBefore = await reserveStrategy.requestInfo(reqId);
        expect(infoBefore.isExit).to.eq(false);
        expect(infoBefore.amount).to.eq(stakeAmount);
        expect(infoBefore.claimed).to.eq(false);

        const vaultInfoBefore = await allocation.stakeInfo(reserveStrategy);
        expect(vaultInfoBefore.totalStake).to.equal(stakeAmount);
        expect(vaultInfoBefore.totalAllocation).to.equal(0);

        // jump to readyAt and refund
        await time.setNextBlockTimestamp(expectedReadyAt);

        const refundTx = deposit.refundDeposit(reserveStrategy, reqId, owner);

        await expect(refundTx)
          .to.changeEtherBalances([reserveStrategy, owner], [-stakeAmount, stakeAmount]);

        await expect(refundTx)
          .to.emit(reserveStrategy, "AllocationRefunded")
          .withArgs(reqId, owner, stakeAmount);

        // request should be cleaned / marked claimed
        const infoAfter = await reserveStrategy.requestInfo(reqId);
        expect(infoAfter.claimed).to.eq(true);
        expect(infoAfter.claimable).to.eq(false);

        const vaultInfoAfter = await allocation.stakeInfo(reserveStrategy);
        expect(vaultInfoAfter.totalStake).to.equal(0);
        expect(vaultInfoAfter.totalAllocation).to.equal(0);

        // cannot claim after refund
        await expect(deposit.claimDeposit(reserveStrategy, reqId, owner))
          .to.be.reverted;
      });

      it("refunds exit request (withdraw flow), restores vault shares", async function () {
        const {
          signers, hyperStaking, lumiaDiamond, reserveStrategy, reserveAssetPrice,
        } = await loadFixture(deployHyperStaking);
        const { deposit, allocation, lockbox } = hyperStaking;
        const { realAssets } = lumiaDiamond;
        const { owner, strategyManager } = signers;

        const stakeAmount = parseEther("6");
        await deposit.deposit(reserveStrategy, owner, stakeAmount, { value: stakeAmount });

        const { vaultShares } = await shared.getDerivedTokens(
          lumiaDiamond.hyperlaneHandler,
          await reserveStrategy.getAddress(),
        );

        // user should have vault shares after deposit (price 2:1 means shares == stakeAmount)
        const sharesBeforeRedeem = await vaultShares.balanceOf(owner);
        expect(sharesBeforeRedeem).to.eq(stakeAmount);

        // make exit async
        const exitDelay = 2 * 24 * 3600; // 2 days
        await reserveStrategy.connect(strategyManager).setReadyAtOffsets(0, exitDelay);

        const totalAllocation = stakeAmount * parseEther("1") / reserveAssetPrice;

        const vaultInfoBefore = await allocation.stakeInfo(reserveStrategy);
        expect(vaultInfoBefore.totalStake).to.equal(stakeAmount);
        expect(vaultInfoBefore.totalAllocation).to.equal(totalAllocation);

        // redeem part -> creates pending claim
        const redeemStake = parseEther("2");
        const expectedAllocation = redeemStake * parseEther("1") / reserveAssetPrice;

        await realAssets.redeem(reserveStrategy, owner, owner, redeemStake);

        const claimId = await shared.getLastClaimId(deposit, reserveStrategy, owner);

        // sanity: pending claim exists
        const claim = (await deposit.pendingWithdrawClaims([claimId]))[0];
        expect(claim.strategy).to.eq(await reserveStrategy.getAddress());
        expect(claim.expectedAmount).to.eq(redeemStake);

        // after redeem, shares should be burned
        const sharesAfterRedeem = await vaultShares.balanceOf(owner);
        expect(sharesAfterRedeem).to.eq(sharesBeforeRedeem - redeemStake);

        const vaultInfoMid = await allocation.stakeInfo(reserveStrategy);
        expect(vaultInfoMid.totalStake).to.equal(stakeAmount);
        expect(vaultInfoMid.totalAllocation).to.equal(totalAllocation - expectedAllocation);

        // refund instead of claimWithdraws
        const ts0 = await shared.getCurrentBlockTimestamp();
        const expectedReadyAt = ts0 + exitDelay;
        expect(claim.unlockTime).to.closeTo(expectedReadyAt, 3);

        await time.setNextBlockTimestamp(claim.unlockTime);

        const refundTx = deposit.refundWithdraw(claimId, owner);

        // refund should return allocation back (revenueAsset) and then restore shares
        await expect(refundTx).to.changeTokenBalance(vaultShares, owner, redeemStake);

        await expect(refundTx)
          .to.emit(reserveStrategy, "ExitRefunded")
          .withArgs(claimId, lockbox, expectedAllocation);

        // pending claim should be cleared
        const deleted = (await deposit.pendingWithdrawClaims([claimId]))[0];
        expect(deleted.strategy).to.eq(ZeroAddress);
        expect(deleted.unlockTime).to.eq(0);
        expect(deleted.eligible).to.eq(ZeroAddress);
        expect(deleted.expectedAmount).to.eq(0);

        // stakeInfo should be restored
        const vaultInfoAfter = await allocation.stakeInfo(reserveStrategy);
        expect(vaultInfoAfter.totalStake).to.equal(stakeAmount);
        expect(vaultInfoAfter.totalAllocation).to.equal(totalAllocation);

        // cannot claim after refund
        await expect(deposit.claimWithdraws([claimId], owner))
          .to.be.reverted;
      });

      it("reverts refund if request is not ready yet (too early)", async function () {
        const { hyperStaking, lumiaDiamond, reserveStrategy, signers } = await loadFixture(deployHyperStaking);
        const { deposit } = hyperStaking;
        const { realAssets } = lumiaDiamond;
        const { owner, strategyManager } = signers;

        await deposit.deposit(reserveStrategy, owner, parseEther("3"), { value: parseEther("3") });

        const exitDelay = 24 * 3600; // 1 day
        await reserveStrategy.connect(strategyManager).setReadyAtOffsets(0, exitDelay);

        await realAssets.redeem(reserveStrategy, owner, owner, parseEther("1"));

        const claimId = await shared.getLastClaimId(deposit, reserveStrategy, owner);

        // too early refund should revert (same gating as claim)
        await expect(deposit.refundWithdraw(claimId, owner))
          .to.be.reverted;
      });
    });
  });

  describe("Dinero Strategy", function () {
    afterEach(async () => {
      const c = globalThis.$invChecker;
      if (c) await c.check();
    });

    it("staking deposit to dinero strategy should aquire apxEth", async function () {
      const { signers, hyperStaking, autoPxEth, dineroStrategy } = await loadFixture(deployHyperStaking);
      const { deposit, hyperFactory, lockbox, allocation } = hyperStaking;
      const { owner } = signers;

      const stakeAmount = parseEther("8");
      const apxEthPrice = parseEther("1");

      const expectedFee = 0n;
      const expectedAsset = stakeAmount - expectedFee;
      const expectedShares = autoPxEth.convertToShares(expectedAsset);

      // events
      const reqId = 1;
      const readyAt = 0;
      const depositTx = await deposit.deposit(dineroStrategy, owner, stakeAmount, { value: stakeAmount });

      await expect(depositTx)
        .to.emit(dineroStrategy, "AllocationRequested")
        .withArgs(reqId, owner, expectedAsset, readyAt);

      await expect(depositTx)
        .to.emit(dineroStrategy, "AllocationClaimed")
        .withArgs(reqId, lockbox.target, expectedShares);

      // Strategy
      const stakeCurrency = await dineroStrategy.stakeCurrency() as CurrencyStruct;
      expect(stakeCurrency.token).to.equal(shared.nativeTokenAddress);
      expect(await dineroStrategy.revenueAsset()).to.equal(autoPxEth);

      // Vault
      expect((await hyperFactory.vaultInfo(dineroStrategy)).stakeCurrency).to.deep.equal([shared.nativeTokenAddress]);
      expect((await hyperFactory.vaultInfo(dineroStrategy)).strategy).to.equal(dineroStrategy);
      expect((await hyperFactory.vaultInfo(dineroStrategy)).revenueAsset).to.equal(autoPxEth);

      // StakeInfo
      expect((await allocation.stakeInfo(dineroStrategy)).totalStake).to.equal(stakeAmount);
      expect((await allocation.stakeInfo(dineroStrategy)).totalAllocation).to.equal(stakeAmount * apxEthPrice / parseEther("1"));

      // apxETH balance
      expect(await autoPxEth.balanceOf(lockbox)).to.equal(stakeAmount * apxEthPrice / parseEther("1"));
    });

    it("unstaking from to dinero strategy should exchange apxEth back to eth", async function () {
      const {
        signers, hyperStaking, lumiaDiamond, autoPxEth, dineroStrategy,
      } = await loadFixture(deployHyperStaking);
      const { deposit, hyperFactory, lockbox, allocation } = hyperStaking;
      const { realAssets } = lumiaDiamond;
      const { owner } = signers;

      const blockTime = await shared.getCurrentBlockTimestamp();

      const stakeAmount = parseEther("3");
      const apxEthPrice = parseEther("1");

      // use the same block time for all transactions, because of autoPxEth rewards mechanism

      await time.setNextBlockTimestamp(blockTime);
      const expectedAllocation = await dineroStrategy.previewAllocation(stakeAmount);
      await deposit.deposit(dineroStrategy, owner, stakeAmount, { value: stakeAmount });

      await time.setNextBlockTimestamp(blockTime);

      expect((await allocation.stakeInfo(dineroStrategy)).totalStake).to.equal(stakeAmount);
      expect((await allocation.stakeInfo(dineroStrategy)).totalAllocation).to.equal(expectedAllocation);

      const reqId = 2; // 1 - deposit
      const readyAt = 0;
      await time.setNextBlockTimestamp(blockTime);
      await expect(realAssets.redeem(dineroStrategy, owner, owner, stakeAmount))
        .to.emit(dineroStrategy, "ExitRequested")
        .withArgs(reqId, owner, expectedAllocation, readyAt);

      expect(expectedAllocation).to.be.eq(stakeAmount * apxEthPrice / parseEther("1"));

      expect((await hyperFactory.vaultInfo(dineroStrategy)).revenueAsset).to.equal(autoPxEth);

      const lastClaimId = await shared.getLastClaimId(deposit, dineroStrategy, owner);
      await shared.claimAtDeadline(deposit, lastClaimId, owner);

      expect((await allocation.stakeInfo(dineroStrategy)).totalStake).to.equal(0);
      expect((await allocation.stakeInfo(dineroStrategy)).totalAllocation).to.equal(0);

      expect(await autoPxEth.balanceOf(lockbox)).to.equal(0);
    });
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
