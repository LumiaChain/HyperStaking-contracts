import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, ignition, network } from "hardhat";
import { Signer, parseEther, parseUnits, ZeroAddress } from "ethers";

import DineroStrategyModule from "../ignition/modules/DineroStrategy";
import PirexMockModule from "../ignition/modules/test/PirexMock";
import SuperformMockModule from "../ignition/modules/test/SuperformMock";

import * as shared from "./shared";
import TxCostTracker from "./txCostTracker";
import { PirexEth } from "../typechain-types";

import { SingleDirectSingleVaultStateReqStruct } from "../typechain-types/contracts/external/superform/core/BaseRouter";

describe("Strategy", function () {
  async function getMockedPirex() {
    const [, , rewardRecipient] = await ethers.getSigners();
    const { pxEth, upxEth, pirexEth, autoPxEth } = await ignition.deploy(PirexMockModule);

    // increase rewards buffer
    await (pirexEth.connect(rewardRecipient) as PirexEth).harvest(await ethers.provider.getBlockNumber(), { value: parseEther("100") });

    return { pxEth, upxEth, pirexEth, autoPxEth };
  }

  async function getMockedSuperform() {
    const [superManager, alice] = await ethers.getSigners();
    const testUSDC = await shared.deloyTestERC20("Test USD Coin", "tUSDC", 6);
    const erc4626Vault = await shared.deloyTestERC4626Vault(testUSDC);

    await testUSDC.mint(alice.address, parseUnits("1000000", 6));

    const { superformFactory, superformRouter, superVault, superPositions } = await ignition.deploy(SuperformMockModule, {
      parameters: {
        SuperformMockModule: {
          erc4626VaultAddress: await erc4626Vault.getAddress(),
        },
      },
    });

    const superformId = await superVault.superformIds(0);

    const [superformAddress,,] = await superformFactory.getSuperform(superformId);
    const superform = await ethers.getContractAt("BaseForm", superformAddress);

    // -------

    return { superformFactory, superformRouter, superVault, superPositions, superformId, superform, superManager, testUSDC, erc4626Vault, alice };
  }

  const superUSDCDeposit = async (
    amount: bigint,
    outputAmount: bigint,
    maxSlippage: bigint,
    receiver: Signer,
  ) => {
    const { superformRouter, testUSDC, superformId } = await loadFixture(getMockedSuperform);

    await testUSDC.connect(receiver).approve(superformRouter, amount);
    const routerReq: SingleDirectSingleVaultStateReqStruct = {
      superformData: {
        superformId,
        amount,
        outputAmount,
        maxSlippage,
        liqRequest: {
          txData: "0x",
          token: testUSDC,
          interimToken: ZeroAddress,
          bridgeId: 1,
          liqDstChainId: 0,
          nativeAmount: 0,
        },
        permit2data: "0x",
        hasDstSwap: false,
        retain4626: false,
        receiverAddress: receiver,
        receiverAddressSP: receiver,
        extraFormData: "0x",
      },
    };

    await superformRouter.connect(receiver).singleDirectSingleVaultDeposit(routerReq);
  };

  async function deployHyperStaking() {
    const [owner, stakingManager, strategyVaultManager, bob, alice] = await ethers.getSigners();
    const { diamond, staking, factory, tier1, tier2 } = await shared.deployTestHyperStaking(0n);

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

    await factory.connect(strategyVaultManager).addStrategy(
      ethPoolId,
      reserveStrategy,
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

    await factory.connect(strategyVaultManager).addStrategy(
      ethPoolId,
      dineroStrategy,
      defaultRevenueFee,
    );

    // -------------------------------------------

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, factory, tier1, tier2, // diamond facets
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
        staking, factory, tier1, tier2, testWstETH, ethPoolId, reserveStrategy, reserveAssetPrice, owner, alice,
      } = await loadFixture(deployHyperStaking);

      const ownerAmount = parseEther("2");
      const aliceAmount = parseEther("8");

      expect(await testWstETH.balanceOf(factory.target)).to.equal(0);
      expect(await reserveStrategy.assetPrice()).to.equal(reserveAssetPrice);
      expect(await reserveStrategy.convertToAllocation(ownerAmount)).to.equal(ownerAmount * parseEther("1") / reserveAssetPrice);

      // event
      await expect(staking.stakeDeposit(ethPoolId, reserveStrategy, ownerAmount, owner, { value: ownerAmount }))
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(owner, ownerAmount, ownerAmount * parseEther("1") / reserveAssetPrice);

      expect(await testWstETH.balanceOf(factory.target)).to.equal(ownerAmount * parseEther("1") / reserveAssetPrice);

      // event
      await expect(staking.stakeDeposit(ethPoolId, reserveStrategy, aliceAmount, alice, { value: aliceAmount }))
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(alice, aliceAmount, aliceAmount * parseEther("1") / reserveAssetPrice);

      // Owner UserInfo
      expect((await staking.userPoolInfo(ethPoolId, owner)).staked).to.equal(ownerAmount);
      expect((await staking.userPoolInfo(ethPoolId, owner)).stakeLocked).to.equal(ownerAmount);
      expect((await tier1.userTier1Info(reserveStrategy, owner)).stakeLocked).to.equal(ownerAmount);
      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint).to.equal(parseUnits("1", 36) / reserveAssetPrice);
      expect(await tier1.userContribution(reserveStrategy, owner)).to.equal(parseEther("0.2"));

      // Alice UserInfo
      expect((await staking.userPoolInfo(ethPoolId, alice)).staked).to.equal(aliceAmount);
      expect((await staking.userPoolInfo(ethPoolId, alice)).stakeLocked).to.equal(aliceAmount);
      expect((await tier1.userTier1Info(reserveStrategy, alice)).stakeLocked).to.equal(aliceAmount);
      expect((await tier1.userTier1Info(reserveStrategy, alice)).allocationPoint)
        .to.equal(await reserveStrategy.convertToAllocation(parseEther("1")));
      expect(await tier1.userContribution(reserveStrategy, alice)).to.equal(parseEther("0.8")); // 80%

      // VaultInfo
      expect((await factory.vaultInfo(reserveStrategy)).strategy).to.equal(reserveStrategy);
      expect((await factory.vaultInfo(reserveStrategy)).poolId).to.equal(ethPoolId);
      expect((await factory.vaultInfo(reserveStrategy)).asset).to.equal(testWstETH);

      // TiersInfo
      expect((await tier1.vaultTier1Info(reserveStrategy)).assetAllocation).to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);
      expect((await tier1.vaultTier1Info(reserveStrategy)).totalStakeLocked).to.equal(ownerAmount + aliceAmount);
      expect((await tier1.vaultTier1Info(reserveStrategy)).revenueFee).to.equal(0);

      expect((await tier2.vaultTier2Info(reserveStrategy)).vaultToken).to.not.equal(ZeroAddress);

      expect(await testWstETH.balanceOf(factory.target)).to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);
    });

    it("check state after exit", async function () {
      const {
        staking, factory, tier1, testWstETH, ethPoolId, reserveStrategy, reserveAssetPrice, owner,
      } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("2.4");
      const withdrawAmount = parseEther("0.6");
      const diffAmount = stakeAmount - withdrawAmount;

      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, owner, { value: stakeAmount });

      // event
      await expect(staking.stakeWithdraw(ethPoolId, reserveStrategy, withdrawAmount, owner))
        .to.emit(reserveStrategy, "Exit")
        .withArgs(owner, withdrawAmount * parseEther("1") / reserveAssetPrice, withdrawAmount);

      // UserInfo
      expect((await staking.userPoolInfo(ethPoolId, owner)).staked).to.equal(diffAmount);
      expect((await staking.userPoolInfo(ethPoolId, owner)).stakeLocked).to.equal(diffAmount);

      expect((await tier1.userTier1Info(reserveStrategy, owner)).stakeLocked).to.equal(diffAmount);
      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint)
        .to.equal(await reserveStrategy.convertToAllocation(parseEther("1")));
      expect(await tier1.userContribution(reserveStrategy, owner)).to.equal(parseEther("1"));

      // TiersInfo
      expect((await tier1.vaultTier1Info(reserveStrategy)).assetAllocation).to.equal(diffAmount * parseEther("1") / reserveAssetPrice);
      expect((await tier1.vaultTier1Info(reserveStrategy)).totalStakeLocked).to.equal(diffAmount);

      expect(await testWstETH.balanceOf(factory.target)).to.equal(diffAmount * parseEther("1") / reserveAssetPrice);

      // withdraw all
      await staking.stakeWithdraw(ethPoolId, reserveStrategy, diffAmount, owner);

      // UserInfo
      expect((await staking.userPoolInfo(ethPoolId, owner)).staked).to.equal(0);
      expect((await staking.userPoolInfo(ethPoolId, owner)).stakeLocked).to.equal(0);

      expect((await tier1.userTier1Info(reserveStrategy, owner)).stakeLocked).to.equal(0);
      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint).to.equal(parseUnits("1", 36) / reserveAssetPrice);
      expect(await tier1.userContribution(reserveStrategy, owner)).to.equal(0);

      // TiersInfo
      expect((await tier1.vaultTier1Info(reserveStrategy)).assetAllocation).to.equal(0);
      expect((await tier1.vaultTier1Info(reserveStrategy)).totalStakeLocked).to.equal(0);

      expect(await testWstETH.balanceOf(factory.target)).to.equal(0);
    });

    it("allocation point should depend on weighted price", async function () {
      const {
        staking, tier1, ethPoolId, reserveStrategy, owner,
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
      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint).to.equal(price1);

      await reserveStrategy.setAssetPrice(price2);
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount2, owner, { value: stakeAmount2 });

      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint)
        .to.equal((reversePrice(price1) * stakeAmount1 + reversePrice(price2) * stakeAmount2) / (stakeAmount1 + stakeAmount2));

      await reserveStrategy.setAssetPrice(price3);
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount3, owner, { value: stakeAmount3 });

      const expectedPrice = // weighted average
        (reversePrice(price1) * stakeAmount1 + reversePrice(price2) * stakeAmount2 + reversePrice(price3) * stakeAmount3) /
        (stakeAmount1 + stakeAmount2 + stakeAmount3);

      expect((await tier1.userTier1Info(reserveStrategy, owner)).allocationPoint)
        .to.equal(expectedPrice);
    });

    it("user generates revenue when asset increases in price", async function () {
      const {
        staking, tier1, ethPoolId, reserveStrategy, alice,
      } = await loadFixture(deployHyperStaking);

      const price1 = parseEther("2");
      const price2 = parseEther("4");

      const stakeAmount = parseEther("3.0");

      await reserveStrategy.setAssetPrice(price1);
      await staking.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount });

      // increase price
      await reserveStrategy.setAssetPrice(price2);

      const expectedRevenue = stakeAmount * price2 / price1 - stakeAmount;

      expect(await tier1.userRevenue(reserveStrategy, alice)).to.equal(expectedRevenue);

      // revenue should decrease proportionaly to withdraw
      await staking.connect(alice).stakeWithdraw(ethPoolId, reserveStrategy, stakeAmount / 2n, alice);

      expect(await tier1.userRevenue(reserveStrategy, alice)).to.equal(expectedRevenue / 2n);
    });

    it("users revenue should work with a more complex scenario", async function () {
      const {
        staking, tier1, ethPoolId, reserveStrategy, bob, alice,
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
      const {
        staking, tier1, ethPoolId, reserveStrategy, alice, strategyVaultManager,
      } = await loadFixture(deployHyperStaking);
      const gasCosts = new TxCostTracker();

      const revenueFee = parseEther("0.1"); // 10%
      await tier1.connect(strategyVaultManager).setRevenueFee(reserveStrategy, revenueFee);

      const price1 = parseEther("2");
      const price2 = parseEther("2.5");
      const stakeAmount = parseEther("3.0");

      const aliceBalanceBefore = await ethers.provider.getBalance(alice);

      await reserveStrategy.setAssetPrice(price1);

      await gasCosts.includeTx(
        await staking.connect(alice).stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount }),
      );

      await reserveStrategy.setAssetPrice(price2);
      const revenue = stakeAmount * price2 / price1 - stakeAmount;

      await gasCosts.includeTx(
        await staking.connect(alice).stakeWithdraw(ethPoolId, reserveStrategy, stakeAmount, alice),
      );

      const expectedFee = revenueFee * revenue / parseEther("1");

      // alice balance after
      const expectedAliceBalance = aliceBalanceBefore + revenue - expectedFee - gasCosts.getTotalCosts();
      expect(await ethers.provider.getBalance(alice)).to.equal(expectedAliceBalance);
    });

    describe("Errors", function () {
      it("OnlyStrategyVaultManager", async function () {
        const {
          factory, ethPoolId, reserveStrategy, alice, defaultRevenueFee,
        } = await loadFixture(deployHyperStaking);

        await expect(factory.addStrategy(
          ethPoolId,
          reserveStrategy,
          defaultRevenueFee,
        ))
          .to.be.reverted;

        await expect(factory.connect(alice).addStrategy(
          ethPoolId,
          reserveStrategy,
          defaultRevenueFee,
        ))
          // hardhat unfortunately does not recognize custom errors from child contracts
          // .to.be.revertedWithCustomError(factory, "OnlyStrategyVaultManager");
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
          factory, strategyVaultManager, ethPoolId, reserveStrategy, defaultRevenueFee,
        } = await loadFixture(deployHyperStaking);

        await expect(factory.connect(strategyVaultManager).addStrategy(
          ethPoolId,
          reserveStrategy,
          defaultRevenueFee,
        ))
          .to.be.revertedWithCustomError(factory, "VaultAlreadyExist");
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
      const { staking, factory, tier1, autoPxEth, ethPoolId, dineroStrategy, owner } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("8");
      const apxEthPrice = parseEther("1");

      const expectedFee = 0n;
      const expectedAsset = stakeAmount - expectedFee;
      const expectedShares = autoPxEth.convertToShares(expectedAsset);

      // event
      await expect(staking.stakeDeposit(ethPoolId, dineroStrategy, stakeAmount, owner, { value: stakeAmount }))
        .to.emit(dineroStrategy, "Allocate")
        .withArgs(
          owner,
          expectedAsset,
          expectedShares,
        );

      expect((await staking.userPoolInfo(ethPoolId, owner)).staked).to.equal(stakeAmount);
      expect((await factory.vaultInfo(dineroStrategy)).asset).to.equal(autoPxEth.target);

      expect((await tier1.vaultTier1Info(dineroStrategy)).assetAllocation).to.equal(stakeAmount * apxEthPrice / parseEther("1"));
      expect((await tier1.vaultTier1Info(dineroStrategy)).totalStakeLocked).to.equal(stakeAmount);

      expect(await autoPxEth.balanceOf(factory.target)).to.equal(stakeAmount * apxEthPrice / parseEther("1"));
    });

    it("unstaking from to dinero strategy should exchange apxEth back to eth", async function () {
      const { staking, factory, tier1, autoPxEth, ethPoolId, dineroStrategy, owner } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("3");
      const apxEthPrice = parseEther("1");

      await staking.stakeDeposit(ethPoolId, dineroStrategy, stakeAmount, owner, { value: stakeAmount });

      await expect(staking.stakeWithdraw(ethPoolId, dineroStrategy, stakeAmount, owner))
        .to.emit(dineroStrategy, "Exit")
        .withArgs(owner, stakeAmount * apxEthPrice / parseEther("1"), anyValue);

      expect((await staking.userPoolInfo(ethPoolId, owner)).staked).to.equal(0);
      expect((await tier1.userTier1Info(dineroStrategy, owner)).stakeLocked).to.equal(0);
      expect((await factory.vaultInfo(dineroStrategy)).asset).to.equal(autoPxEth.target);

      expect((await tier1.vaultTier1Info(dineroStrategy)).assetAllocation).to.equal(0);
      expect((await tier1.vaultTier1Info(dineroStrategy)).totalStakeLocked).to.equal(0);

      expect(await autoPxEth.balanceOf(factory.target)).to.equal(0);
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

  describe("Superform Strategy", function () {
    describe("Superform Mock", function () {
      it("overall tests of the mock", async function () {
        const { superformFactory, superVault, superPositions, testUSDC, erc4626Vault } = await loadFixture(getMockedSuperform);
        const [, alice] = await ethers.getSigners();

        const superformId = await superVault.superformIds(0);
        expect(await superformFactory.isSuperform(superformId)).to.equal(true);
        expect(await superformFactory.vaultToSuperforms(erc4626Vault.target, 0)).to.equal(superformId);

        expect(await superPositions.name()).to.equal("Super Test Positions");
        expect(await superPositions.symbol()).to.equal("STP");
        expect(await superPositions.dynamicURI()).to.equal("dynamicURI");

        const [superformAddress, formId, chainId] = await superformFactory.getSuperform(superformId);

        expect(formId).to.equal(3);
        expect(chainId).to.equal(network.config.chainId);

        const superform = await ethers.getContractAt("ERC4626Form", superformAddress);

        expect(await superform.getVaultName()).to.equal(await erc4626Vault.name());
        expect(await superform.getVaultSymbol()).to.equal(await erc4626Vault.symbol());

        expect(await superform.vault()).to.equal(erc4626Vault.target);
        expect(await superform.asset()).to.equal(testUSDC.target);

        expect(await superPositions.balanceOf(alice.address, superformId)).to.equal(0);
        expect(await superPositions.totalSupply(superformId)).to.equal(0);
      });

      it("It should be possible to deposit USDC using superRouter", async function () {
        const { superform, superformId, superPositions, alice } = await loadFixture(getMockedSuperform);

        // deposit amount
        const amount = parseUnits("100", 6);

        const maxSlippage = 50n; // 0.5%
        const outputAmount = await superform.previewDepositTo(amount);

        await superUSDCDeposit(amount, outputAmount, maxSlippage, alice);

        const outputAmountSlipped = outputAmount * (10000n - maxSlippage) / 10000n;
        expect(await superPositions.balanceOf(alice.address, superformId)).to.be.gt(outputAmountSlipped);
      });

      it("It should be possible to transmute superPositions to aERC20", async function () {
        const { superform, superformId, superPositions, alice } = await loadFixture(getMockedSuperform);

        const amount = parseUnits("100", 6);
        const maxSlippage = 50n; // 0.5%
        const outputAmount = await superform.previewDepositTo(amount);

        await superUSDCDeposit(amount, outputAmount, maxSlippage, alice);

        const balance = await superPositions.balanceOf(alice, superformId);

        await superPositions.registerAERC20(superformId);
        expect(await superPositions.aERC20Exists(superformId)).to.be.eq(true);

        const aerc20Address = await superPositions.getERC20TokenAddress(superformId);
        const aerc20 = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", aerc20Address);

        await superPositions.connect(alice).transmuteToERC20(alice, superformId, balance, alice);

        // after transmutimg the ERC115 balance should be 0
        expect(await superPositions.balanceOf(alice, superformId)).to.be.eq(0);

        // the same amount is in aERC20
        expect(await aerc20.balanceOf(alice)).to.be.eq(balance);

        // transmute back to ERC1155 (in 2 steps)
        await aerc20.connect(alice).approve(superPositions, balance - 100n);
        await superPositions.connect(alice).transmuteToERC1155A(alice, superformId, balance - 100n, alice);

        expect(await superPositions.balanceOf(alice, superformId)).to.be.eq(balance - 100n);
        expect(await aerc20.balanceOf(alice)).to.be.eq(100);

        await aerc20.connect(alice).approve(superPositions, 100n);
        await superPositions.connect(alice).transmuteToERC1155A(alice, superformId, 100, alice);

        expect(await superPositions.connect(alice).balanceOf(alice, superformId)).to.be.eq(balance);
        expect(await aerc20.balanceOf(alice)).to.be.eq(0);
      });
    });
  });
});
