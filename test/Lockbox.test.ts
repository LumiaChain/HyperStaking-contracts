import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { parseEther, ZeroAddress } from "ethers";

import * as shared from "./shared";

describe("Lockbox", function () {
  async function deployHyperStaking() {
    const [owner, stakingManager, strategyVaultManager, bob, alice] = await ethers.getSigners();

    const {
      mailbox, interchainFactory, diamond, staking, factory, tier1, tier2, lockbox,
    } = await shared.deployTestHyperStaking(0n);

    // --------------------- Deploy Tokens ----------------------

    const testReserveAsset = await shared.deloyTestERC20("Test Reserve Asset", "tRaETH");

    // ------------------ Create Staking Pools ------------------

    const { nativeTokenAddress, ethPoolId } = await shared.createNativeStakingPool(staking);

    // -------------------- Apply Strategies --------------------

    const defaultRevenueFee = parseEther("0"); // 0% fee

    // strategy asset price to eth 2:1
    const reserveAssetPrice = parseEther("2");

    const reserveStrategy = await shared.createReserveStrategy(
      diamond, nativeTokenAddress, await testReserveAsset.getAddress(), reserveAssetPrice,
    );

    await factory.connect(strategyVaultManager).addStrategy(
      ethPoolId,
      reserveStrategy,
      testReserveAsset,
      defaultRevenueFee,
    );

    // set fee after strategy is added
    const mailboxFee = parseEther("0.05");
    await mailbox.connect(owner).setFee(mailboxFee);

    const vaultTokenAddress = (await tier2.vaultTier2Info(reserveStrategy)).vaultToken;
    const vaultToken = await ethers.getContractAt("VaultToken", vaultTokenAddress);

    const lpTokenAddress = await interchainFactory.lpTokens(vaultTokenAddress);
    const lpToken = await ethers.getContractAt("LumiaLPToken", lpTokenAddress);

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, factory, tier1, tier2, lockbox, // diamond facets
      mailbox, interchainFactory, testReserveAsset, reserveStrategy, vaultToken, lpToken, // test contracts
      ethPoolId, // ids
      defaultRevenueFee, reserveAssetPrice, mailboxFee, // values
      nativeTokenAddress, owner, stakingManager, strategyVaultManager, alice, bob, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("Lockbox", function () {
    it("stake deposit to tier2 with non-zero mailbox fee", async function () {
      const {
        staking, ethPoolId, reserveStrategy, vaultToken, lpToken, mailboxFee, owner, alice,
      } = await loadFixture(deployHyperStaking);

      const lpBefore = await lpToken.balanceOf(alice);

      const stakeAmount = parseEther("2");

      const tier2 = 2;
      await expect(staking.stakeDepositTier2(
        ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount + mailboxFee },
      ))
        .to.emit(staking, "StakeDeposit")
        .withArgs(owner, alice, ethPoolId, reserveStrategy, stakeAmount, tier2);

      const lpAfter = await lpToken.balanceOf(alice);
      expect(lpAfter).to.be.gt(lpBefore);

      // more accurate amount calculation
      const allocation = await reserveStrategy.convertToAllocation(stakeAmount);
      const lpAmount = await vaultToken.previewDeposit(allocation);

      expect(lpAfter).to.be.eq(lpBefore + lpAmount);

      // stake values should be 0 in tier2
      expect((await staking.userPoolInfo(ethPoolId, alice)).stakeLocked).to.equal(0);
      expect((await staking.poolInfo(ethPoolId)).totalStake).to.equal(0);
    });

    it("mailbox fee is needed when adding strategy too", async function () {
      const {
        diamond, staking, factory, lockbox, mailboxFee, strategyVaultManager,
      } = await loadFixture(deployHyperStaking);

      // new pool and strategy
      const { nativeTokenAddress, ethPoolId } = await shared.createNativeStakingPool(staking);
      const asset2 = await shared.deloyTestERC20("Test Reserve Asset 2", "t2");

      const strategy2 = await shared.createReserveStrategy(
        diamond, nativeTokenAddress, await asset2.getAddress(), parseEther("1"),
      );

      // revert if mailbox fee is not sent
      await expect(factory.connect(strategyVaultManager).addStrategy(
        ethPoolId,
        strategy2,
        asset2,
        0n,
      )).to.be.reverted;

      expect( // in a real scenario fee could depend on the token address, correct name and symbol
        await lockbox.quoteDispatchTokenDeploy(ZeroAddress, "Test Reserve Asset 2", "t2"),
      ).to.equal(mailboxFee);

      await factory.connect(strategyVaultManager).addStrategy(
        ethPoolId,
        strategy2,
        asset2,
        0n,
        { value: mailboxFee },
      );
    });
  });

  describe.only("Hyperlane Mailbox Messages", function () {
    // remove null bytes from (solidity bytes32) the end of a string
    const decodeString = (s: string) => s.replace(/\0+$/, "");

    async function deployTestWrapper() {
      return await ethers.deployContract("TestHyperlaneMessages", []);
    }

    it("serialization and deserialization", async function () {
      const testWrapper = await loadFixture(deployTestWrapper);

      // TokenDeploy

      const message1 = {
        tokenAddress: ZeroAddress,
        name: "Test Token",
        symbol: "TT",
        metadata: "0x1234",
      };

      const bytes1 = await testWrapper.serializeTokenDeploy(
        message1.tokenAddress,
        message1.name,
        message1.symbol,
        message1.metadata,
      );

      expect(await testWrapper.messageType(bytes1)).to.equal(0);
      expect(await testWrapper.tokenAddress(bytes1)).to.equal(message1.tokenAddress);
      expect(decodeString(await testWrapper.name(bytes1))).to.equal(message1.name);
      expect(decodeString(await testWrapper.symbol(bytes1))).to.equal(message1.symbol);
      expect(await testWrapper.tokenDeployMetadata(bytes1)).to.equal(message1.metadata);

      // TokenBridge

      const message2 = {
        vaultToken: ZeroAddress,
        sender: ZeroAddress,
        amount: parseEther("1"),
        metadata: "0x1234",
      };

      const bytes2 = await testWrapper.serializeTokenBridge(
        message2.vaultToken,
        message2.sender,
        message2.amount,
        message2.metadata,
      );

      expect(await testWrapper.messageType(bytes2)).to.equal(1);
      expect(await testWrapper.vaultToken(bytes2)).to.equal(message2.vaultToken);
      expect(await testWrapper.sender(bytes2)).to.equal(message2.sender);
      expect(await testWrapper.amount(bytes2)).to.equal(message2.amount);
      expect(await testWrapper.tokenBridgeMetadata(bytes2)).to.equal(message2.metadata);
    });

    it("string limitations", async function () {
      const testWrapper = await loadFixture(deployTestWrapper);

      const message = {
        tokenAddress: ZeroAddress,
        name: "Test Token with a little longer name than usual, still working?",
        symbol: "TTSYMBOLEXTENDED 123456789",
        metadata: "0x",
      };

      const bytes1 = await testWrapper.serializeTokenDeploy(
        message.tokenAddress,
        message.name,
        message.symbol,
        message.metadata,
      );

      expect(decodeString(await testWrapper.name(bytes1))).to.equal(message.name);
      expect(decodeString(await testWrapper.symbol(bytes1))).to.equal(message.symbol);

      // but

      await testWrapper.stringToBytes32("X".repeat(32)); // ok
      await expect(testWrapper.stringToBytes32("X".repeat(33)))
        .to.be.revertedWith("stringToBytes32: overflow");

      await testWrapper.stringToBytes64("X".repeat(64)); // ok
      await expect(testWrapper.stringToBytes64("X".repeat(65)))
        .to.be.revertedWith("stringToBytes64: overflow");
    });
  });
});
