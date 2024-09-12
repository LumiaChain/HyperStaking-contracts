import { /* time, */ loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

import DiamondModule from "../ignition/modules/Diamond";
import HyperStakingModule from "../ignition/modules/HyperStaking";
import RevertingContractModule from "../ignition/modules/RevertingContract";

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

    const stakingFacet = await hre.ethers.getContractAt("StakingFacet", diamond);

    await stakingFacet.init();
    const nativeTokenAddress = await stakingFacet.nativeTokenAddress();
    const ethPoolId = await stakingFacet.generatePoolId(nativeTokenAddress, 0);

    return { diamond, stakingFacet, ethPoolId, owner, alice };
  }

  describe("Diamond", function () {
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
      const { stakingFacet, ethPoolId, owner, alice } = await loadFixture(deployHyperStaking);

      const stakeAmount = hre.ethers.parseEther("5");
      await expect(stakingFacet.stakeDeposit(ethPoolId, stakeAmount, owner, { value: stakeAmount }))
        .to.changeEtherBalances(
          [owner, stakingFacet],
          [-stakeAmount, stakeAmount],
        );

      // event
      await expect(stakingFacet.stakeDeposit(ethPoolId, stakeAmount, owner, { value: stakeAmount }))
        .to.emit(stakingFacet, "StakeDeposit")
        .withArgs(owner.address, ethPoolId, stakeAmount, owner.address);

      const stakeAmountForAlice = hre.ethers.parseEther("11");
      await expect(stakingFacet.stakeDeposit(
        ethPoolId, stakeAmountForAlice, alice, { value: stakeAmountForAlice }),
      )
        .to.emit(stakingFacet, "StakeDeposit")
        .withArgs(owner.address, ethPoolId, stakeAmountForAlice, alice.address);

      // UserInfo
      expect(
        (await stakingFacet.userInfo(ethPoolId, owner.address)).amount,
      ).to.equal(stakeAmount * 2n);
      expect(
        (await stakingFacet.userInfo(ethPoolId, alice.address)).amount,
      ).to.equal(stakeAmountForAlice);

      // PoolInfo
      const poolInfo = await stakingFacet.poolInfo(ethPoolId);
      expect(poolInfo.totalStake).to.equal(stakeAmount * 2n + stakeAmountForAlice);
    });

    it("Should be able to withdraw stake", async function () {
      const { stakingFacet, ethPoolId, owner, alice } = await loadFixture(deployHyperStaking);

      const stakeAmount = hre.ethers.parseEther("2.2");
      const withdrawAmount = hre.ethers.parseEther("0.5");

      await stakingFacet.stakeDeposit(ethPoolId, stakeAmount, owner, { value: stakeAmount });

      await expect(stakingFacet.stakeWithdraw(ethPoolId, withdrawAmount, owner))
        .to.changeEtherBalances(
          [owner, stakingFacet],
          [withdrawAmount, -withdrawAmount],
        );

      await expect(stakingFacet.stakeWithdraw(ethPoolId, withdrawAmount, owner))
        .to.emit(stakingFacet, "StakeWithdraw")
        .withArgs(owner.address, ethPoolId, withdrawAmount, owner.address);

      await expect(stakingFacet.stakeWithdraw(ethPoolId, withdrawAmount, alice))
        .to.changeEtherBalances(
          [owner, stakingFacet, alice],
          [0, -withdrawAmount, withdrawAmount],
        );

      // UserInfo
      expect(
        (await stakingFacet.userInfo(ethPoolId, owner.address)).amount,
      ).to.equal(stakeAmount - 3n * withdrawAmount);
      expect(
        (await stakingFacet.userInfo(ethPoolId, alice.address)).amount,
      ).to.equal(0);

      // PoolInfo
      const poolInfo = await stakingFacet.poolInfo(ethPoolId);
      expect(poolInfo.totalStake).to.equal(stakeAmount - 3n * withdrawAmount);
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
        const { stakingFacet, ethPoolId, owner } = await loadFixture(deployHyperStaking);

        const stakeAmount = hre.ethers.parseEther("1");
        const value = hre.ethers.parseEther("0.99");

        await expect(stakingFacet.stakeDeposit(ethPoolId, stakeAmount, owner, { value }))
          .to.be.revertedWithCustomError(stakingFacet, "DepositBadValue");
      });

      it("WithdrawFailedCall", async function () {
        const { stakingFacet, ethPoolId, owner } = await loadFixture(deployHyperStaking);

        // test contract which reverts on payable call
        const { revertingContract } = await hre.ignition.deploy(RevertingContractModule);

        const stakeAmount = hre.ethers.parseEther("1");

        await stakingFacet.stakeDeposit(ethPoolId, stakeAmount, owner, { value: stakeAmount });
        await expect(stakingFacet.stakeWithdraw(ethPoolId, stakeAmount, revertingContract))
          .to.be.revertedWithCustomError(stakingFacet, "WithdrawFailedCall");
      });

      it("PoolDoesNotExist", async function () {
        const { stakingFacet, owner } = await loadFixture(deployHyperStaking);

        const badPoolId = "0xabca816169f82123e129cf759e8d851bd8a678458c95df05d183240301c330f9";

        await expect(stakingFacet.stakeDeposit(badPoolId, 1, owner, { value: 1 }))
          .to.be.revertedWithCustomError(stakingFacet, "PoolDoesNotExist");
      });
    });
  });
});
