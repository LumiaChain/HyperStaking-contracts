import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import { parseEther } from "ethers";

import DiamondModule from "../ignition/modules/Diamond";
import HyperStakingModule from "../ignition/modules/HyperStaking";
import RevertingContractModule from "../ignition/modules/RevertingContract";

import * as shared from "./shared";

describe("Staking", function () {
  async function deployDiamond() {
    const [owner, alice] = await hre.ethers.getSigners();
    const { diamond } = await hre.ignition.deploy(DiamondModule);

    const ownershipFacet = await hre.ethers.getContractAt("OwnershipFacet", diamond);

    return { diamond, ownershipFacet, owner, alice };
  }

  async function deployHyperStaking() {
    const [owner, alice] = await hre.ethers.getSigners();
    const { diamond, staking, vault } = await hre.ignition.deploy(HyperStakingModule);

    // --------------------- Deploy Tokens --------------------

    const testERC20 = await shared.deloyTestERC20("Test ERC20 Token", "tERC20");
    const testWstETH = await shared.deloyTestERC20("Test Wrapped Liquid Staked ETH", "tWstETH");

    // ------------------ Create Staking Pools ------------------

    const erc20PoolId = await shared.createStakingPool(staking, testERC20);
    const { nativeTokenAddress, ethPoolId } = await shared.createNativeStakingPool(staking);

    // -------------------- Apply Strategies --------------------

    const reserveStrategy1 = await shared.createReserveStrategy(
      diamond, nativeTokenAddress, await testWstETH.getAddress(), parseEther("1"),
    );
    const reserveStrategy2 = await shared.createReserveStrategy(
      diamond, await testERC20.getAddress(), await testWstETH.getAddress(), parseEther("2"),
    );

    const reserveStrategyAssetSupply = parseEther("55");
    await testWstETH.approve(reserveStrategy1.target, reserveStrategyAssetSupply);
    await reserveStrategy1.supplyRevenueAsset(reserveStrategyAssetSupply);

    await testWstETH.approve(reserveStrategy2.target, reserveStrategyAssetSupply);
    await reserveStrategy2.supplyRevenueAsset(reserveStrategyAssetSupply);

    // strategy with neutral to eth 1:1 asset price
    await vault.addStrategy(ethPoolId, reserveStrategy1, testWstETH);

    // strategy with erc20 staking token and 2:1 asset price
    await vault.addStrategy(erc20PoolId, reserveStrategy2, testWstETH);

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, vault, // diamond facets
      testERC20, testWstETH, reserveStrategy1, reserveStrategy2, // test contracts
      ethPoolId, erc20PoolId, // ids
      nativeTokenAddress, owner, alice, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("Diamond Ownership", function () {
    it("should set the right owner", async function () {
      const { ownershipFacet, owner } = await loadFixture(deployDiamond);

      expect(await ownershipFacet.owner()).to.equal(owner.address);
    });

    it("it should be able to transfer ownership", async function () {
      const { ownershipFacet, alice } = await loadFixture(deployDiamond);

      await ownershipFacet.transferOwnership(alice.address);
      expect(await ownershipFacet.owner()).to.equal(alice.address);
    });
  });

  // TODO ERC20 staking pools

  describe("Staking", function () {
    it("should be able to deposit stake", async function () {
      const { staking, ethPoolId, reserveStrategy1, owner, alice } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("5");
      await expect(staking.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value: stakeAmount }))
        .to.changeEtherBalances(
          [owner, reserveStrategy1],
          [-stakeAmount, stakeAmount],
        );

      // event
      await expect(staking.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value: stakeAmount }))
        .to.emit(staking, "StakeDeposit")
        .withArgs(owner.address, owner.address, ethPoolId, reserveStrategy1, stakeAmount);

      const stakeAmountForAlice = parseEther("11");
      await expect(staking.connect(alice).stakeDeposit(
        ethPoolId, reserveStrategy1, stakeAmountForAlice, alice, { value: stakeAmountForAlice }),
      )
        .to.emit(staking, "StakeDeposit")
        .withArgs(alice.address, alice.address, ethPoolId, reserveStrategy1, stakeAmountForAlice);

      // UserInfo
      expect(
        (await staking.userPoolInfo(ethPoolId, owner.address)).staked,
      ).to.equal(stakeAmount * 2n);
      expect(
        (await staking.userPoolInfo(ethPoolId, alice.address)).staked,
      ).to.equal(stakeAmountForAlice);

      // PoolInfo
      const poolInfo = await staking.poolInfo(ethPoolId);
      expect(poolInfo.totalStake).to.equal(stakeAmount * 2n + stakeAmountForAlice);
    });

    it("should be able to withdraw stake", async function () {
      const { staking, ethPoolId, reserveStrategy1, owner, alice } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("6.4");
      const withdrawAmount = parseEther(".8");

      await staking.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value: stakeAmount });

      await expect(staking.stakeWithdraw(ethPoolId, reserveStrategy1, withdrawAmount, owner))
        .to.changeEtherBalances(
          [owner, reserveStrategy1],
          [withdrawAmount, -withdrawAmount],
        );

      await expect(staking.stakeWithdraw(ethPoolId, reserveStrategy1, withdrawAmount, owner))
        .to.emit(staking, "StakeWithdraw")
        .withArgs(owner.address, owner.address, ethPoolId, reserveStrategy1, withdrawAmount, anyValue);

      const precisionError = 4n; // 4wei
      await expect(staking.stakeWithdraw(ethPoolId, reserveStrategy1, withdrawAmount, alice))
        .to.changeEtherBalances(
          [alice, reserveStrategy1],
          [withdrawAmount - precisionError, -withdrawAmount + precisionError],
        );

      // UserInfo
      expect(
        (await staking.userPoolInfo(ethPoolId, owner.address)).staked,
      ).to.equal(stakeAmount - 3n * withdrawAmount);
      expect(
        (await staking.userPoolInfo(ethPoolId, alice.address)).staked,
      ).to.equal(0);

      // PoolInfo
      const poolInfo = await staking.poolInfo(ethPoolId);
      expect(poolInfo.totalStake).to.equal(stakeAmount - 3n * withdrawAmount);
    });

    it("erc20 token pool should allow to stake and withdraw", async function () {
      const { staking, testERC20, erc20PoolId, reserveStrategy2, owner, alice } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("7.8");
      const withdrawAmount = parseEther("1.4");

      await testERC20.approve(staking, stakeAmount);
      await staking.stakeDeposit(erc20PoolId, reserveStrategy2, stakeAmount, owner);

      const precisionError = 2n; // 2wei
      await expect(staking.stakeWithdraw(erc20PoolId, reserveStrategy2, withdrawAmount, owner))
        .to.changeTokenBalances(testERC20,
          [owner, reserveStrategy2],
          [withdrawAmount - precisionError, -withdrawAmount + precisionError],
        );

      await expect(staking.stakeWithdraw(erc20PoolId, reserveStrategy2, withdrawAmount, owner))
        .to.emit(staking, "StakeWithdraw")
        .withArgs(owner.address, owner.address, erc20PoolId, reserveStrategy2, withdrawAmount, withdrawAmount);

      await expect(staking.stakeWithdraw(erc20PoolId, reserveStrategy2, withdrawAmount, alice))
        .to.changeTokenBalances(testERC20,
          [alice, reserveStrategy2],
          [withdrawAmount, -withdrawAmount],
        );

      // UserInfo
      expect(
        (await staking.userPoolInfo(erc20PoolId, owner.address)).staked,
      ).to.equal(stakeAmount - 3n * withdrawAmount);
      expect(
        (await staking.userPoolInfo(erc20PoolId, alice.address)).staked,
      ).to.equal(0);

      // PoolInfo
      const poolInfo = await staking.poolInfo(erc20PoolId);
      expect(poolInfo.totalStake).to.equal(stakeAmount - 3n * withdrawAmount);
    });

    it("poolId generation check", async function () {
      const { staking } = await loadFixture(deployHyperStaking);

      const randomCurrency = { token: "0x5FbDB2315678afecb367f032d93F642f64180aa3" };

      const generatedPoolId = await staking.generatePoolId(randomCurrency, 5);
      const expectedPoolId = hre.ethers.keccak256(
        hre.ethers.solidityPacked(["address", "uint96"], [randomCurrency.token, 5]),
      );
      expect(generatedPoolId).to.equal(expectedPoolId);

      const generatedPoolId2 = await staking.generatePoolId(randomCurrency, 9);
      const expectedPoolId2 = hre.ethers.keccak256(
      // <-           160 bits address           -><-   96 bits uint96   ->
        "0x5FbDB2315678afecb367f032d93F642f64180aa3000000000000000000000009",
      );
      expect(generatedPoolId2).to.equal(expectedPoolId2);

      const generatedPoolId3 = await staking.generatePoolId(randomCurrency, 0);
      const expectedPoolId3 = "0x39de3650bb6cfdcc3483b5957dd17fd3a957201d789c5e61c8215dda41caea22";

      expect(generatedPoolId3).to.equal(expectedPoolId3);
    });

    describe("CurrencyHandler Errors", function () {
      it("Invalid deposit value", async function () {
        const { staking, ethPoolId, reserveStrategy1, owner } = await loadFixture(deployHyperStaking);

        const stakeAmount = parseEther("1");
        const value = parseEther("0.99");

        await expect(staking.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value }))
          .to.be.revertedWith("Invalid native value sent");
      });

      it("Transfer call failed", async function () {
        const { staking, ethPoolId, reserveStrategy1, owner } = await loadFixture(deployHyperStaking);

        // test contract which reverts on payable call
        const { revertingContract } = await hre.ignition.deploy(RevertingContractModule);

        const stakeAmount = parseEther("1");

        await staking.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value: stakeAmount });
        await expect(staking.stakeWithdraw(ethPoolId, reserveStrategy1, stakeAmount, revertingContract))
          .to.be.revertedWith("Transfer call failed");
      });

      // TODO "Transfer insufficient balance"

      it("PoolDoesNotExist", async function () {
        const { staking, reserveStrategy1, owner } = await loadFixture(deployHyperStaking);

        const badPoolId = "0xabca816169f82123e129cf759e8d851bd8a678458c95df05d183240301c330f9";

        await expect(staking.stakeDeposit(badPoolId, reserveStrategy1, 1, owner, { value: 1 }))
          .to.be.revertedWithCustomError(staking, "PoolDoesNotExist");
      });
    });
  });
});
