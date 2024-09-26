import { /* time, */ loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import { parseEther } from "ethers";

import DiamondModule from "../ignition/modules/Diamond";
import HyperStakingModule from "../ignition/modules/HyperStaking";
import ReserveStrategyModule from "../ignition/modules/ReserveStrategy";
import RevertingContractModule from "../ignition/modules/RevertingContract";
import TestERC20Module from "../ignition/modules/TestERC20";

describe("Staking", function () {
  async function deployDiamond() {
    const [owner, alice] = await hre.ethers.getSigners();
    const { diamond } = await hre.ignition.deploy(DiamondModule);

    const ownershipFacet = await hre.ethers.getContractAt("OwnershipFacet", diamond);

    return { diamond, ownershipFacet, owner, alice };
  }

  async function deployHyperStaking() {
    const [owner, alice] = await hre.ethers.getSigners();
    const { diamond } = await hre.ignition.deploy(HyperStakingModule);
    const stakingFacet = await hre.ethers.getContractAt("IStaking", diamond);
    const vaultFacet = await hre.ethers.getContractAt("IStrategyVault", diamond);

    // -------------------- Create Staking Pools --------------------

    // testErc20
    const { testERC20 } = await hre.ignition.deploy(TestERC20Module, {
      parameters: {
        TestERC20Module: {
          symbol: "testERC20",
          name: "Test ERC20 Token",
        },
      },
    });

    await stakingFacet.createStakingPool(testERC20);
    const erc20PoolId = await stakingFacet.generatePoolId(testERC20, 0);

    // testWstETH
    const testWstETH = (await hre.ignition.deploy(TestERC20Module, {
      parameters: {
        TestERC20Module: {
          symbol: "testWstETH",
          name: "Test Wrapped Liquid Staked ETH",
        },
      },
    })).testERC20;

    const nativeTokenAddress = await stakingFacet.nativeTokenAddress();
    await stakingFacet.createStakingPool(nativeTokenAddress);
    const ethPoolId = await stakingFacet.generatePoolId(nativeTokenAddress, 0);

    // -------------------- Apply Strategy --------------------

    const reserveStrategy1 = (await hre.ignition.deploy(ReserveStrategyModule, {
      parameters: {
        ReserveStrategyModule: {
          diamond: await diamond.getAddress(),
          asset: await testWstETH.getAddress(),
          assetPrice: parseEther("1"),
        },
      },
    })).reserveStrategy;

    const reserveStrategy2 = (await hre.ignition.deploy(ReserveStrategyModule, {
      parameters: {
        ReserveStrategyModule: {
          diamond: await diamond.getAddress(),
          asset: await testWstETH.getAddress(),
          assetPrice: parseEther("2"),
        },
      },
    })).reserveStrategy;

    const reserveStrategyAssetSupply = parseEther("55");
    await testWstETH.approve(reserveStrategy1.target, reserveStrategyAssetSupply);
    await reserveStrategy1.supplyRevenueAsset(reserveStrategyAssetSupply);

    await testWstETH.approve(reserveStrategy2.target, reserveStrategyAssetSupply);
    await reserveStrategy2.supplyRevenueAsset(reserveStrategyAssetSupply);

    // strategy with neutral to eth 1:1 asset price
    await vaultFacet.addStrategy(ethPoolId, reserveStrategy1, testWstETH);

    // strategy with erc20 staking token and 2:1 asset price
    await vaultFacet.addStrategy(erc20PoolId, reserveStrategy2, testWstETH);

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      stakingFacet, vaultFacet, // diamond facets
      testWstETH, reserveStrategy1, reserveStrategy2, // test contracts
      ethPoolId, erc20PoolId, // ids
      owner, alice, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("Diamond Ownership", function () {
    it("Should set the right owner", async function () {
      const { ownershipFacet, owner } = await loadFixture(deployDiamond);

      expect(await ownershipFacet.owner()).to.equal(owner.address);
    });

    it("It should be able to transfer ownership", async function () {
      const { ownershipFacet, alice } = await loadFixture(deployDiamond);

      await ownershipFacet.transferOwnership(alice.address);
      expect(await ownershipFacet.owner()).to.equal(alice.address);
    });
  });

  describe("Staking", function () {
    it("Should be able to deposit stake", async function () {
      const { stakingFacet, ethPoolId, reserveStrategy1, owner, alice } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("5");
      await expect(stakingFacet.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value: stakeAmount }))
        .to.changeEtherBalances(
          [owner, reserveStrategy1],
          [-stakeAmount, stakeAmount],
        );

      // event
      await expect(stakingFacet.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value: stakeAmount }))
        .to.emit(stakingFacet, "StakeDeposit")
        .withArgs(owner.address, owner.address, ethPoolId, reserveStrategy1, stakeAmount);

      const stakeAmountForAlice = parseEther("11");
      await expect(stakingFacet.stakeDeposit(
        ethPoolId, reserveStrategy1, stakeAmountForAlice, alice, { value: stakeAmountForAlice }),
      )
        .to.emit(stakingFacet, "StakeDeposit")
        .withArgs(owner.address, alice.address, ethPoolId, reserveStrategy1, stakeAmountForAlice);

      // UserInfo
      expect(
        (await stakingFacet.userPoolInfo(ethPoolId, owner.address)).staked,
      ).to.equal(stakeAmount * 2n);
      expect(
        (await stakingFacet.userPoolInfo(ethPoolId, alice.address)).staked,
      ).to.equal(stakeAmountForAlice);

      // PoolInfo
      const poolInfo = await stakingFacet.poolInfo(ethPoolId);
      expect(poolInfo.totalStake).to.equal(stakeAmount * 2n + stakeAmountForAlice);
    });

    it("Should be able to withdraw stake", async function () {
      const { stakingFacet, ethPoolId, reserveStrategy1, owner, alice } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("6.4");
      const withdrawAmount = parseEther(".8");

      await stakingFacet.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value: stakeAmount });

      await expect(stakingFacet.stakeWithdraw(ethPoolId, reserveStrategy1, withdrawAmount, owner))
        .to.changeEtherBalances(
          [owner, reserveStrategy1],
          [withdrawAmount, -withdrawAmount],
        );

      await expect(stakingFacet.stakeWithdraw(ethPoolId, reserveStrategy1, withdrawAmount, owner))
        .to.emit(stakingFacet, "StakeWithdraw")
        .withArgs(owner.address, owner.address, ethPoolId, reserveStrategy1, withdrawAmount, anyValue);

      // TODO epsilon
      // await expect(stakingFacet.stakeWithdraw(ethPoolId, reserveStrategy1, withdrawAmount, alice))
      //  .to.changeEtherBalances(
      //    [owner, stakingFacet, alice],
      //    [0, -withdrawAmount, withdrawAmount],
      //  );

      // UserInfo
      expect(
        (await stakingFacet.userPoolInfo(ethPoolId, owner.address)).staked,
      ).to.equal(stakeAmount - 2n * withdrawAmount);
      expect(
        (await stakingFacet.userPoolInfo(ethPoolId, alice.address)).staked,
      ).to.equal(0);

      // PoolInfo
      const poolInfo = await stakingFacet.poolInfo(ethPoolId);
      expect(poolInfo.totalStake).to.equal(stakeAmount - 2n * withdrawAmount);
    });

    it("PoolId generation check", async function () {
      const { stakingFacet } = await loadFixture(deployHyperStaking);

      const randomTokenAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3";

      const generatedPoolId = await stakingFacet.generatePoolId(randomTokenAddress, 5);
      const expectedPoolId = hre.ethers.keccak256(
        hre.ethers.solidityPacked(["address", "uint96"], [randomTokenAddress, 5]),
      );
      expect(generatedPoolId).to.equal(expectedPoolId);

      const generatedPoolId2 = await stakingFacet.generatePoolId(randomTokenAddress, 9);
      const expectedPoolId2 = hre.ethers.keccak256(
      // <-           160 bits address           -><-   96 bits uint96   ->
        "0x5FbDB2315678afecb367f032d93F642f64180aa3000000000000000000000009",
      );
      expect(generatedPoolId2).to.equal(expectedPoolId2);

      const generatedPoolId3 = await stakingFacet.generatePoolId(randomTokenAddress, 0);
      const expectedPoolId3 = "0x39de3650bb6cfdcc3483b5957dd17fd3a957201d789c5e61c8215dda41caea22";

      expect(generatedPoolId3).to.equal(expectedPoolId3);
    });

    describe("Errors", function () {
      it("DepositBadValue", async function () {
        const { stakingFacet, ethPoolId, reserveStrategy1, owner } = await loadFixture(deployHyperStaking);

        const stakeAmount = parseEther("1");
        const value = parseEther("0.99");

        await expect(stakingFacet.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value }))
          .to.be.revertedWithCustomError(stakingFacet, "DepositBadValue");
      });

      it("WithdrawFailedCall", async function () {
        const { stakingFacet, ethPoolId, reserveStrategy1, owner } = await loadFixture(deployHyperStaking);

        // test contract which reverts on payable call
        const { revertingContract } = await hre.ignition.deploy(RevertingContractModule);

        const stakeAmount = parseEther("1");

        await stakingFacet.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value: stakeAmount });
        await expect(stakingFacet.stakeWithdraw(ethPoolId, reserveStrategy1, stakeAmount, revertingContract))
          .to.be.revertedWithCustomError(stakingFacet, "WithdrawFailedCall");
      });

      it("PoolDoesNotExist", async function () {
        const { stakingFacet, reserveStrategy1, owner } = await loadFixture(deployHyperStaking);

        const badPoolId = "0xabca816169f82123e129cf759e8d851bd8a678458c95df05d183240301c330f9";

        await expect(stakingFacet.stakeDeposit(badPoolId, reserveStrategy1, 1, owner, { value: 1 }))
          .to.be.revertedWithCustomError(stakingFacet, "PoolDoesNotExist");
      });
    });
  });
});
