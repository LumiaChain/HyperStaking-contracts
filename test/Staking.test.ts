import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, ignition } from "hardhat";
import { parseEther, ZeroAddress } from "ethers";

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
    const [owner, stakingManager, strategyVaultManager, alice, bob] = await ethers.getSigners();

    // --------------------- Deploy Tokens --------------------

    const testERC20 = await shared.deloyTestERC20("Test ERC20 Token", "tERC20");
    const testWstETH = await shared.deloyTestERC20("Test Wrapped Liquid Staked ETH", "tWstETH");
    const erc4626Vault = await shared.deloyTestERC4626Vault(testERC20);

    // --------------------- Hyperstaking Diamond --------------------

    const { diamond, staking, vaultFactory } = await shared.deployTestHyperStaking(0n, erc4626Vault);

    // ------------------ Create Staking Pools ------------------

    const erc20PoolId = await shared.createStakingPool(staking, testERC20);
    const { nativeTokenAddress, ethPoolId } = await shared.createNativeStakingPool(staking);

    // -------------------- Apply Strategies --------------------

    const defaultRevenueFee = parseEther("0"); // 0% fee

    const reserveStrategy1 = await shared.createReserveStrategy(
      diamond, nativeTokenAddress, await testWstETH.getAddress(), parseEther("1"),
    );
    const reserveStrategy2 = await shared.createReserveStrategy(
      diamond, await testERC20.getAddress(), await testWstETH.getAddress(), parseEther("2"),
    );

    // strategy with neutral to eth 1:1 asset price
    await vaultFactory.connect(strategyVaultManager).addStrategy(
      ethPoolId,
      shared.nativeCurrency(),
      reserveStrategy1,
      "eth vault1",
      "vETH1",
      defaultRevenueFee,
    );

    // strategy with erc20 staking token and 2:1 asset price
    await vaultFactory.connect(strategyVaultManager).addStrategy(
      erc20PoolId,
      shared.erc20Currency(await testERC20.getAddress()),
      reserveStrategy2,
      "erc20 vault2",
      "vERC2",
      defaultRevenueFee,
    );

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, vaultFactory, // diamond facets
      testERC20, testWstETH, reserveStrategy1, reserveStrategy2, // test contracts
      ethPoolId, erc20PoolId, // ids
      nativeTokenAddress, owner, stakingManager, strategyVaultManager, alice, bob, // addresses
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
    it("creating pools should be restricted ", async function () {
      const { staking, bob } = await loadFixture(deployHyperStaking);

      await expect(staking.connect(bob).createStakingPool({ token: ZeroAddress }))
        .to.be.reverted;
    });

    it("staking can be paused", async function () {
      const { staking, ethPoolId, reserveStrategy1, stakingManager, bob } = await loadFixture(deployHyperStaking);

      // pause
      await expect(staking.connect(bob).pauseStaking()).to.be.reverted;
      await expect(staking.connect(stakingManager).pauseStaking()).to.not.be.reverted;

      await expect(staking.stakeDeposit(ethPoolId, reserveStrategy1, 100, bob, { value: 100 }))
        .to.be.reverted;

      await expect(staking.connect(bob).stakeWithdraw(ethPoolId, reserveStrategy1, 100, bob)).to.be.reverted;

      // unpause
      await expect(staking.connect(bob).unpauseStaking()).to.be.reverted;
      await expect(staking.connect(stakingManager).unpauseStaking()).to.not.be.reverted;

      await staking.stakeDeposit(ethPoolId, reserveStrategy1, 100, bob, { value: 100 });
      await staking.connect(bob).stakeWithdraw(ethPoolId, reserveStrategy1, 100, bob);
    });

    it("should be able to deposit stake", async function () {
      const { staking, ethPoolId, reserveStrategy1, owner, alice } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("5");
      await expect(staking.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value: stakeAmount }))
        .to.changeEtherBalances(
          [owner, reserveStrategy1],
          [-stakeAmount, stakeAmount],
        );

      // event
      const tier1 = 1;
      await expect(staking.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value: stakeAmount }))
        .to.emit(staking, "StakeDeposit")
        .withArgs(owner, owner, ethPoolId, reserveStrategy1, stakeAmount, tier1);

      const stakeAmountForAlice = parseEther("11");
      await expect(staking.connect(alice).stakeDeposit(
        ethPoolId, reserveStrategy1, stakeAmountForAlice, alice, { value: stakeAmountForAlice }),
      )
        .to.emit(staking, "StakeDeposit")
        .withArgs(alice, alice, ethPoolId, reserveStrategy1, stakeAmountForAlice, tier1);

      // UserInfo
      expect(
        (await staking.userPoolInfo(ethPoolId, owner)).staked,
      ).to.equal(stakeAmount * 2n);
      expect(
        (await staking.userPoolInfo(ethPoolId, alice)).staked,
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
        .withArgs(owner, owner, ethPoolId, reserveStrategy1, withdrawAmount, anyValue);

      const precisionError = 4n; // 4wei
      await expect(staking.stakeWithdraw(ethPoolId, reserveStrategy1, withdrawAmount, alice))
        .to.changeEtherBalances(
          [alice, reserveStrategy1],
          [withdrawAmount - precisionError, -withdrawAmount + precisionError],
        );

      // UserInfo
      expect(
        (await staking.userPoolInfo(ethPoolId, owner)).staked,
      ).to.equal(stakeAmount - 3n * withdrawAmount);
      expect(
        (await staking.userPoolInfo(ethPoolId, alice)).staked,
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
        .withArgs(owner, owner, erc20PoolId, reserveStrategy2, withdrawAmount, withdrawAmount);

      await expect(staking.stakeWithdraw(erc20PoolId, reserveStrategy2, withdrawAmount, alice))
        .to.changeTokenBalances(testERC20,
          [alice, reserveStrategy2],
          [withdrawAmount, -withdrawAmount],
        );

      // UserInfo
      expect(
        (await staking.userPoolInfo(erc20PoolId, owner)).staked,
      ).to.equal(stakeAmount - 3n * withdrawAmount);
      expect(
        (await staking.userPoolInfo(erc20PoolId, alice)).staked,
      ).to.equal(0);

      // PoolInfo
      const poolInfo = await staking.poolInfo(erc20PoolId);
      expect(poolInfo.totalStake).to.equal(stakeAmount - 3n * withdrawAmount);
    });

    it("poolId generation check", async function () {
      const { staking } = await loadFixture(deployHyperStaking);

      const randomCurrency = { token: "0x5FbDB2315678afecb367f032d93F642f64180aa3" };

      const generatedPoolId = await staking.generatePoolId(randomCurrency, 5);
      const expectedPoolId = ethers.keccak256(
        ethers.solidityPacked(["address", "uint96"], [randomCurrency.token, 5]),
      );
      expect(generatedPoolId).to.equal(expectedPoolId);

      const generatedPoolId2 = await staking.generatePoolId(randomCurrency, 9);
      const expectedPoolId2 = ethers.keccak256(
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
          .to.be.revertedWith("Insufficient native value");
      });

      it("Transfer call failed", async function () {
        const { staking, ethPoolId, reserveStrategy1, owner } = await loadFixture(deployHyperStaking);

        // test contract which reverts on payable call
        const { revertingContract } = await ignition.deploy(RevertingContractModule);

        const stakeAmount = parseEther("1");

        await staking.stakeDeposit(ethPoolId, reserveStrategy1, stakeAmount, owner, { value: stakeAmount });
        await expect(staking.stakeWithdraw(ethPoolId, reserveStrategy1, stakeAmount, revertingContract))
          .to.be.revertedWith("Transfer call failed");
      });

      it("PoolDoesNotExist", async function () {
        const { staking, reserveStrategy1, owner } = await loadFixture(deployHyperStaking);

        const badPoolId = "0xabca816169f82123e129cf759e8d851bd8a678458c95df05d183240301c330f9";

        await expect(staking.stakeDeposit(badPoolId, reserveStrategy1, 1, owner, { value: 1 }))
          .to.be.revertedWithCustomError(staking, "PoolDoesNotExist");
      });
    });
  });
});
