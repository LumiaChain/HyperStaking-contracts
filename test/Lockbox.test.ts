import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { parseEther, ZeroAddress } from "ethers";

import * as shared from "./shared";

describe("Lockbox", function () {
  async function deployHyperStaking() {
    const [owner, stakingManager, strategyVaultManager, lumiaFactoryManager, bob, alice] = await ethers.getSigners();

    // --------------------- Deploy Tokens ----------------------

    const testReserveAsset = await shared.deloyTestERC20("Test Reserve Asset", "tRaETH");
    const erc4626Vault = await shared.deloyTestERC4626Vault(testReserveAsset);

    // --------------------- Hyperstaking Diamond --------------------

    const {
      mailbox, interchainFactory, diamond, staking, vaultFactory, tier1, tier2, lockbox,
    } = await shared.deployTestHyperStaking(0n, erc4626Vault);

    // ------------------ Create Staking Pools ------------------

    const { nativeTokenAddress, ethPoolId } = await shared.createNativeStakingPool(staking);

    // -------------------- Apply Strategies --------------------

    const defaultRevenueFee = parseEther("0"); // 0% fee

    // strategy asset price to eth 2:1
    const reserveAssetPrice = parseEther("2");

    const reserveStrategy = await shared.createReserveStrategy(
      diamond, nativeTokenAddress, await testReserveAsset.getAddress(), reserveAssetPrice,
    );

    await vaultFactory.connect(strategyVaultManager).addStrategy(
      ethPoolId,
      shared.nativeCurrency(),
      reserveStrategy,
      "reserve eth vault 1",
      "rETH1",
      defaultRevenueFee,
    );

    // set fee after strategy is added
    const mailboxFee = parseEther("0.05");
    await mailbox.connect(owner).setFee(mailboxFee);

    const { vaultToken, lpToken } = await shared.getDerivedTokens(
      tier2, interchainFactory, await reserveStrategy.getAddress(),
    );

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, vaultFactory, tier1, tier2, lockbox, // diamond facets
      mailbox, interchainFactory, testReserveAsset, reserveStrategy, vaultToken, lpToken, // test contracts
      ethPoolId, // ids
      defaultRevenueFee, reserveAssetPrice, mailboxFee, // values
      nativeTokenAddress, owner, stakingManager, strategyVaultManager, lumiaFactoryManager, alice, bob, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("Lockbox", function () {
    it("lp token properties should be derived from vault token", async function () {
      const {
        diamond, tier2, vaultFactory, interchainFactory, mailbox, ethPoolId, nativeTokenAddress, vaultToken, lpToken, strategyVaultManager, owner,
      } = await loadFixture(deployHyperStaking);

      expect(await lpToken.name()).to.equal(await vaultToken.name());
      expect(await lpToken.symbol()).to.equal(await vaultToken.symbol());
      expect(await lpToken.decimals()).to.equal(await vaultToken.decimals());

      {
        const strangeToken = await shared.deloyTestERC20("Test 14 dec Coin", "t14c", 14);
        const reserveStrategy2 = await shared.createReserveStrategy(
          diamond, nativeTokenAddress, await strangeToken.getAddress(), parseEther("1"),
        );

        const vname = "strange vault";
        const vsymbol = "sv";

        await mailbox.connect(owner).setFee(0n);
        await vaultFactory.connect(strategyVaultManager).addStrategy(
          ethPoolId,
          shared.nativeCurrency(),
          reserveStrategy2,
          vname,
          vsymbol,
          0n,
        );

        const tokens2 = await shared.getDerivedTokens(
          tier2, interchainFactory, await reserveStrategy2.getAddress(),
        );

        expect(await tokens2.vaultToken.name()).to.equal(vname);
        expect(await tokens2.vaultToken.symbol()).to.equal(vsymbol);
        expect(await tokens2.vaultToken.decimals()).to.equal(14); // 14

        expect(await tokens2.lpToken.name()).to.equal(vname);
        expect(await tokens2.lpToken.symbol()).to.equal(vsymbol);
        expect(await tokens2.lpToken.decimals()).to.equal(14); // 14
      }
    });

    it("interchain factory acl", async function () {
      const { interchainFactory, lockbox, lumiaFactoryManager } = await loadFixture(deployHyperStaking);

      // errors
      await expect(interchainFactory.setDestination(123)).to.be.reverted;
      await expect(interchainFactory.setOriginLockbox(ZeroAddress)).to.be.reverted;

      // events
      await expect(interchainFactory.connect(lumiaFactoryManager).setDestination(123))
        .to.emit(interchainFactory, "DestinationUpdated")
        .withArgs(31337, 123);

      await expect(interchainFactory.connect(lumiaFactoryManager).setOriginLockbox(ZeroAddress))
        .to.emit(interchainFactory, "OriginLockboxUpdated")
        .withArgs(lockbox.target, ZeroAddress);
    });

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
      const allocation = await reserveStrategy.previewAllocation(stakeAmount);
      const lpAmount = await vaultToken.previewDeposit(allocation);

      expect(lpAfter).to.be.eq(lpBefore + lpAmount);

      // stake values should be 0 in tier2
      expect((await staking.userPoolInfo(ethPoolId, alice)).stakeLocked).to.equal(0);
      expect((await staking.poolInfo(ethPoolId)).totalStake).to.equal(0);
    });

    it("mailbox fee is needed when adding strategy too", async function () {
      const {
        diamond, staking, vaultFactory, lockbox, mailboxFee, strategyVaultManager,
      } = await loadFixture(deployHyperStaking);

      // new pool and strategy
      const { nativeTokenAddress, ethPoolId } = await shared.createNativeStakingPool(staking);
      const asset2 = await shared.deloyTestERC20("Test Reserve Asset 2", "t2");

      const strategy2 = await shared.createReserveStrategy(
        diamond, nativeTokenAddress, await asset2.getAddress(), parseEther("1"),
      );

      // revert if mailbox fee is not sent
      await expect(vaultFactory.connect(strategyVaultManager).addStrategy(
        ethPoolId,
        shared.nativeCurrency(),
        strategy2,
        "vault2",
        "v2",
        0n,
      )).to.be.reverted;

      expect( // in a real scenario fee could depend on the token address, correct name and symbol
        await lockbox.quoteDispatchTokenDeploy(ZeroAddress, "Test Reserve Asset 2", "t2", 18),
      ).to.equal(mailboxFee);

      await vaultFactory.connect(strategyVaultManager).addStrategy(
        ethPoolId,
        shared.nativeCurrency(),
        strategy2,
        "vault3",
        "v3",
        0n,
        { value: mailboxFee },
      );
    });

    it("redeem on the should triger tier2 leave on the origin chain - non-zero mailbox fee", async function () {
      const {
        staking, ethPoolId, reserveStrategy, mailbox, vaultToken, interchainFactory,
        testReserveAsset, lpToken, mailboxFee, reserveAssetPrice, alice,
      } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("3");
      const expectedLpAmount = stakeAmount * parseEther("1") / reserveAssetPrice;

      await expect(staking.stakeDepositTier2(
        ethPoolId, reserveStrategy, stakeAmount, alice, { value: stakeAmount + mailboxFee },
      ))
        .to.emit(interchainFactory, "TokenBridged")
        .withArgs(vaultToken, lpToken, alice.address, expectedLpAmount);

      const lpAfter = await lpToken.balanceOf(alice);
      expect(lpAfter).to.eq(expectedLpAmount);

      await lpToken.connect(alice).approve(interchainFactory, lpAfter);

      await expect(interchainFactory.connect(alice).redeemLpTokensDispatch(
        vaultToken, alice, lpAfter,
      ))
        .to.be.revertedWithCustomError(mailbox, "DispatchUnderpaid");

      const dispatchFee = await interchainFactory.quoteDispatchTokenRedeem(vaultToken, alice, lpAfter);

      await expect(interchainFactory.redeemLpTokensDispatch(ZeroAddress, alice, lpAfter))
        .to.be.revertedWithCustomError(interchainFactory, "UnrecognizedVaultToken");

      // redeem should return stakeAmount
      const redeemTx = interchainFactory.connect(alice).redeemLpTokensDispatch(
        vaultToken, alice, lpAfter, { value: dispatchFee },
      );

      // lpToken -> vaultAsset -> strategy allocation -> stake withdraw
      await expect(redeemTx).to.changeEtherBalance(alice, stakeAmount - dispatchFee);
      await expect(redeemTx).to.changeTokenBalance(testReserveAsset, vaultToken, -expectedLpAmount);

      expect(await lpToken.balanceOf(alice)).to.eq(0);
    });
  });

  describe("Hyperlane Mailbox Messages", function () {
    // remove null bytes from (solidity bytes32) the end of a string (right padding)
    const decodeString = (s: string) => {
      return s.replace(/\0+$/, "");
    };

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
        decimals: 2,
        metadata: "0x1234",
      };

      const bytes1 = await testWrapper.serializeTokenDeploy(
        message1.tokenAddress,
        message1.name,
        message1.symbol,
        message1.decimals,
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

      // TokenRedeem

      const message3 = {
        vaultToken: ZeroAddress,
        sender: ZeroAddress,
        amount: parseEther("2"),
        metadata: "0x1256",
      };

      const bytes3 = await testWrapper.serializeTokenRedeem(
        message3.vaultToken,
        message3.sender,
        message3.amount,
        message3.metadata,
      );

      expect(await testWrapper.messageType(bytes3)).to.equal(2);
      expect(await testWrapper.vaultToken(bytes3)).to.equal(message3.vaultToken);
      expect(await testWrapper.sender(bytes3)).to.equal(message3.sender);
      expect(await testWrapper.amount(bytes3)).to.equal(message3.amount);
      expect(await testWrapper.tokenBridgeMetadata(bytes3)).to.equal(message3.metadata);
    });

    it("string limitations", async function () {
      const testWrapper = await loadFixture(deployTestWrapper);

      const message = {
        tokenAddress: ZeroAddress,
        name: "Test Token with a little longer name than usual, still working?",
        symbol: "TTSYMBOLEXTENDED 123456789",
        decimals: 15,
        metadata: "0x",
      };

      const bytes1 = await testWrapper.serializeTokenDeploy(
        message.tokenAddress,
        message.name,
        message.symbol,
        message.decimals,
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
