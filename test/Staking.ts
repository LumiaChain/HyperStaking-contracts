import { /* time, */ loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

import DiamondModule from "../ignition/modules/Diamond";
import HyperStakingModule from "../ignition/modules/HyperStaking";

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

    // TODO remove
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
      const { stakingFacet, ethPoolId, owner } = await loadFixture(deployHyperStaking);

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

      // TODO check userInfo, with alice
    });

    it("Should be able to withdraw stake", async function () {
      const { stakingFacet, ethPoolId, owner } = await loadFixture(deployHyperStaking);

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

      // TODO check userInfo, with alice
    });
  });
});
