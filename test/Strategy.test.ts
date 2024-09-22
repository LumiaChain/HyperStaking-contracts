import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { parseEther } from "ethers";

import HyperStakingModule from "../ignition/modules/HyperStaking";
import PirexModule from "../ignition/modules/Pirex";
import TestERC20Module from "../ignition/modules/TestERC20";
import ReserveStrategyModule from "../ignition/modules/ReserveStrategy";
import PirexStrategyModule from "../ignition/modules/PirexStrategy";
import { PirexEth } from "../typechain-types";

describe("Strategy", function () {
  async function deployAndMockPirex() {
    const [owner, alice, rewardRecipient] = await hre.ethers.getSigners();

    const { pxEth, upxEth, pirexEth, autoPxEth } = await hre.ignition.deploy(PirexModule);

    // increase rewards buffer
    await (pirexEth.connect(rewardRecipient) as PirexEth).harvest(await ethers.provider.getBlockNumber(), { value: parseEther("100") });

    return { pxEth, upxEth, pirexEth, autoPxEth, owner, alice };
  }

  async function deployHyperStaking() {
    const [owner, alice] = await hre.ethers.getSigners();
    const { diamond } = await hre.ignition.deploy(HyperStakingModule);

    const stakingFacet = await hre.ethers.getContractAt("IStakingFacet", diamond);
    const vaultFacet = await hre.ethers.getContractAt("IStrategyVault", diamond);

    const { testERC20 } = await hre.ignition.deploy(TestERC20Module, {
      parameters: {
        TestERC20Module: {
          symbol: "testWstETH",
          name: "Test Wrapped Liquid Staked ETH",
        },
      },
    });
    const testWstETH = testERC20;

    await stakingFacet.init();
    const nativeTokenAddress = await stakingFacet.nativeTokenAddress();
    const ethPoolId = await stakingFacet.generatePoolId(nativeTokenAddress, 0);

    // -------------------- Apply Strategies --------------------

    // strategy asset price to eth 2:1
    const reserveAssetPrice = parseEther("2");

    const { reserveStrategy } = await hre.ignition.deploy(ReserveStrategyModule, {
      parameters: {
        ReserveStrategyModule: {
          diamond: await diamond.getAddress(),
          asset: await testWstETH.getAddress(),
          assetPrice: reserveAssetPrice,
        },
      },
    });

    const reserveStrategyAssetSupply = parseEther("55");
    await testWstETH.approve(reserveStrategy.target, reserveStrategyAssetSupply);
    await reserveStrategy.supplyRevenueAsset(reserveStrategyAssetSupply);

    await vaultFacet.init(ethPoolId, reserveStrategy, testWstETH);

    const { pxEth, upxEth, pirexEth, autoPxEth } = await loadFixture(deployAndMockPirex);
    const { pirexStrategy } = await hre.ignition.deploy(PirexStrategyModule, {
      parameters: {
        PirexStrategyModule: {
          diamond: await diamond.getAddress(),
          pxEth: await pxEth.getAddress(),
          pirexEth: await pirexEth.getAddress(),
          autoPxEth: await autoPxEth.getAddress(),
        },
      },
    });

    await vaultFacet.init(ethPoolId, pirexStrategy, autoPxEth);

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      stakingFacet, vaultFacet, // diamond facets
      pxEth, upxEth, pirexEth, autoPxEth, // pirex mock
      testWstETH, reserveStrategy, pirexStrategy, // test contracts
      ethPoolId, // ids
      reserveAssetPrice, reserveStrategyAssetSupply, // values
      owner, alice, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("ReserveStrategy", function () {
    it("Check state after allocation", async function () {
      const {
        stakingFacet, vaultFacet, testWstETH, ethPoolId, reserveStrategy, reserveAssetPrice, owner, alice,
      } = await loadFixture(deployHyperStaking);

      const ownerAmount = parseEther("2");
      const aliceAmount = parseEther("8");

      // event
      await expect(stakingFacet.stakeDeposit(ethPoolId, reserveStrategy, ownerAmount, owner, { value: ownerAmount }))
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(owner.address, ownerAmount, ownerAmount * parseEther("1") / reserveAssetPrice);

      // event
      await expect(stakingFacet.stakeDeposit(
        ethPoolId, reserveStrategy, aliceAmount, alice, { value: aliceAmount }),
      )
        .to.emit(reserveStrategy, "Allocate")
        .withArgs(alice.address, aliceAmount, aliceAmount * parseEther("1") / reserveAssetPrice);

      // UserInfo
      expect(
        (await vaultFacet.userVaultInfo(reserveStrategy, owner.address)).stakeLocked,
      ).to.equal(ownerAmount);

      // UserInfo
      expect((await stakingFacet.userPoolInfo(ethPoolId, owner.address)).staked).to.equal(ownerAmount);
      expect((await vaultFacet.userVaultInfo(reserveStrategy, owner.address)).stakeLocked).to.equal(ownerAmount);
      expect(await vaultFacet.userContribution(reserveStrategy, owner.address)).to.equal(parseEther("0.2"));
      // ---
      expect((await stakingFacet.userPoolInfo(ethPoolId, alice.address)).staked).to.equal(aliceAmount);
      expect((await vaultFacet.userVaultInfo(reserveStrategy, alice.address)).stakeLocked).to.equal(aliceAmount);
      expect(await vaultFacet.userContribution(reserveStrategy, alice.address)).to.equal(parseEther("0.8")); // 80%
      // VaultInfo
      expect((await vaultFacet.vaultInfo(reserveStrategy)).strategy).to.equal(reserveStrategy);
      expect((await vaultFacet.vaultInfo(reserveStrategy)).poolId).to.equal(ethPoolId);
      expect((await vaultFacet.vaultInfo(reserveStrategy)).totalStakeLocked).to.equal(ownerAmount + aliceAmount);
      // AssetInfo
      expect((await vaultFacet.vaultAssetInfo(reserveStrategy)).token).to.equal(testWstETH.target);
      expect((await vaultFacet.vaultAssetInfo(reserveStrategy)).totalShares)
        .to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);

      expect(await testWstETH.balanceOf(vaultFacet.target)).to.equal((ownerAmount + aliceAmount) * parseEther("1") / reserveAssetPrice);
    });

    it("Check state after exit", async function () {
      const {
        stakingFacet, vaultFacet, testWstETH, ethPoolId, reserveStrategy, reserveAssetPrice, owner,
      } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("2.4");
      const withdrawAmount = parseEther("0.6");
      const diffAmount = stakeAmount - withdrawAmount;

      await stakingFacet.stakeDeposit(ethPoolId, reserveStrategy, stakeAmount, owner, { value: stakeAmount });

      // event
      await expect(stakingFacet.stakeWithdraw(ethPoolId, reserveStrategy, withdrawAmount, owner))
        .to.emit(reserveStrategy, "Exit")
        .withArgs(owner.address, withdrawAmount * parseEther("1") / reserveAssetPrice, withdrawAmount);

      // UserInfo
      expect((await stakingFacet.userPoolInfo(ethPoolId, owner.address)).staked).to.equal(diffAmount);
      expect((await vaultFacet.userVaultInfo(reserveStrategy, owner.address)).stakeLocked).to.equal(diffAmount);

      expect(await vaultFacet.userContribution(reserveStrategy, owner.address)).to.equal(parseEther("1"));

      // UserInfo
      expect((await stakingFacet.userPoolInfo(ethPoolId, owner.address)).staked).to.equal(diffAmount);
      expect((await vaultFacet.userVaultInfo(reserveStrategy, owner.address)).stakeLocked).to.equal(diffAmount);
      expect(await vaultFacet.userContribution(reserveStrategy, owner.address)).to.equal(parseEther("1"));
      // VaultInfo
      expect((await vaultFacet.vaultInfo(reserveStrategy)).totalStakeLocked).to.equal(diffAmount);
      // AssetInfo
      expect((await vaultFacet.vaultAssetInfo(reserveStrategy)).token).to.equal(testWstETH.target);

      expect((await vaultFacet.vaultAssetInfo(reserveStrategy)).totalShares)
        .to.equal(diffAmount * parseEther("1") / reserveAssetPrice);
      expect(await testWstETH.balanceOf(vaultFacet.target)).to.equal(diffAmount * parseEther("1") / reserveAssetPrice);

      // withdraw all
      await stakingFacet.stakeWithdraw(ethPoolId, reserveStrategy, diffAmount, owner);

      // UserInfo
      expect((await stakingFacet.userPoolInfo(ethPoolId, owner.address)).staked).to.equal(0);
      expect((await vaultFacet.userVaultInfo(reserveStrategy, owner.address)).stakeLocked).to.equal(0);
      expect(await vaultFacet.userContribution(reserveStrategy, owner.address)).to.equal(0);
      // VaultInfo
      expect((await vaultFacet.vaultInfo(reserveStrategy)).totalStakeLocked).to.equal(0);
      // AssetInfo
      expect((await vaultFacet.vaultAssetInfo(reserveStrategy)).token).to.equal(testWstETH.target);
      expect((await vaultFacet.vaultAssetInfo(reserveStrategy)).totalShares).to.equal(0);
      expect(await testWstETH.balanceOf(vaultFacet.target)).to.equal(0);
    });

    describe("Errors", function () {
      it("VaultDoesNotExist", async function () {
        const { stakingFacet, ethPoolId, owner } = await loadFixture(deployHyperStaking);

        const badStrategy = "0x36fD7e46150d3C0Be5741b0fc8b0b2af4a0D4Dc5";

        await expect(stakingFacet.stakeDeposit(ethPoolId, badStrategy, 1, owner, { value: 1 }))
          .to.be.revertedWithCustomError(stakingFacet, "VaultDoesNotExist");
      });

      it("VaultAlreadyExist", async function () {
        const { vaultFacet, ethPoolId, reserveStrategy } = await loadFixture(deployHyperStaking);

        const randomToken = "0x8Da05a7A689c2C054246B186bEe1C75fcD1df0bC";

        await expect(vaultFacet.init(ethPoolId, reserveStrategy, randomToken))
          .to.be.revertedWithCustomError(vaultFacet, "VaultAlreadyExist");
      });
    });
  });

  describe("Pirex Strategy", function () {
    it("Staking deposit to Pirex strategy should aquire apxEth", async function () {
      const { stakingFacet, vaultFacet, autoPxEth, ethPoolId, pirexStrategy, owner } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("8");

      // event
      await expect(stakingFacet.stakeDeposit(ethPoolId, pirexStrategy, stakeAmount, owner, { value: stakeAmount }))
        .to.emit(pirexStrategy, "Allocate")
        .withArgs(owner.address, stakeAmount, stakeAmount);

      expect((await stakingFacet.userPoolInfo(ethPoolId, owner)).staked).to.equal(stakeAmount);

      expect((await vaultFacet.vaultInfo(pirexStrategy)).totalStakeLocked).to.equal(stakeAmount);
      expect((await vaultFacet.vaultAssetInfo(pirexStrategy)).token).to.equal(autoPxEth.target);
      expect((await vaultFacet.vaultAssetInfo(pirexStrategy)).totalShares).to.equal(stakeAmount);

      expect(await autoPxEth.balanceOf(vaultFacet.target)).to.equal(stakeAmount);
    });

    it("Unstaking from to Pirex strategy should exchange apxEth back to eth", async function () {
      const { stakingFacet, vaultFacet, autoPxEth, ethPoolId, pirexStrategy, owner } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("3");
      await stakingFacet.stakeDeposit(ethPoolId, pirexStrategy, stakeAmount, owner, { value: stakeAmount });

      await expect(stakingFacet.stakeWithdraw(ethPoolId, pirexStrategy, stakeAmount, owner))
        .to.emit(pirexStrategy, "Exit")
        .withArgs(owner.address, stakeAmount, anyValue);

      expect((await stakingFacet.userPoolInfo(ethPoolId, owner.address)).staked).to.equal(0);

      expect((await vaultFacet.userVaultInfo(pirexStrategy, owner.address)).stakeLocked).to.equal(0);
      expect((await vaultFacet.vaultInfo(pirexStrategy)).totalStakeLocked).to.equal(0);
      expect((await vaultFacet.vaultAssetInfo(pirexStrategy)).token).to.equal(autoPxEth.target);
      expect((await vaultFacet.vaultAssetInfo(pirexStrategy)).totalShares).to.equal(0);

      expect(await autoPxEth.balanceOf(vaultFacet.target)).to.equal(0);
    });
  });

  describe("Pirex Mock", function () {
    it("It should be possible to deposit ETH and get pxETH", async function () {
      const { pxEth, pirexEth, owner } = await loadFixture(deployAndMockPirex);

      await pirexEth.deposit(owner.address, false, { value: parseEther("1") });

      expect(await pxEth.balanceOf(owner.address)).to.be.greaterThan(0);
    });

    it("It should be possible to deposit ETH and auto-compund it with apxEth", async function () {
      const { pxEth, pirexEth, autoPxEth, owner } = await loadFixture(deployAndMockPirex);

      await pirexEth.deposit(owner.address, true, { value: parseEther("5") });

      expect(await pxEth.balanceOf(owner.address)).to.equal(0);
      expect(await autoPxEth.balanceOf(owner.address)).to.be.greaterThan(0);
    });

    it("It should be possible to instant Redeem apxEth back to ETH", async function () {
      const { pxEth, pirexEth, autoPxEth, owner, alice } = await loadFixture(deployAndMockPirex);

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
