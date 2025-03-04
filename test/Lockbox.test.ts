import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { parseEther, ZeroAddress } from "ethers";

import * as shared from "./shared";

describe("Lockbox", function () {
  async function deployHyperStaking() {
    const [owner, stakingManager, vaultManager, strategyManager, lumiaFactoryManager, bob, alice] = await ethers.getSigners();

    // -------------------- Deploy Tokens --------------------

    const testReserveAsset = await shared.deloyTestERC20("Test Reserve Asset", "tRaETH");
    const erc4626Vault = await shared.deloyTestERC4626Vault(testReserveAsset);

    // -------------------- Hyperstaking Diamond --------------------

    const {
      mailbox, hyperlaneHandler, routeFactory, diamond, deposit, hyperFactory, tier1, tier2, lockbox,
    } = await shared.deployTestHyperStaking(0n, erc4626Vault);

    // -------------------- Apply Strategies --------------------

    const defaultRevenueFee = parseEther("0"); // 0% fee

    // strategy asset price to eth 2:1
    const reserveAssetPrice = parseEther("2");

    const reserveStrategy = await shared.createReserveStrategy(
      diamond, shared.nativeTokenAddress, await testReserveAsset.getAddress(), reserveAssetPrice,
    );

    await hyperFactory.connect(vaultManager).addStrategy(
      reserveStrategy,
      "reserve eth vault 1",
      "rETH1",
      defaultRevenueFee,
    );

    // set fee after strategy is added
    const mailboxFee = parseEther("0.05");
    await mailbox.connect(owner).setFee(mailboxFee);

    const { vaultToken, lpToken } = await shared.getDerivedTokens(
      tier2, routeFactory, await reserveStrategy.getAddress(),
    );

    // disable lending functionality for reserveStrategy
    await routeFactory.connect(lumiaFactoryManager).updateLendingProperties(reserveStrategy, false, 0);

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      deposit, hyperFactory, tier1, tier2, lockbox, // diamond facets
      mailbox, hyperlaneHandler, routeFactory, testReserveAsset, reserveStrategy, vaultToken, lpToken, // test contracts
      defaultRevenueFee, reserveAssetPrice, mailboxFee, // values
      owner, stakingManager, vaultManager, strategyManager, lumiaFactoryManager, alice, bob, // addresses
    };
    /* eslint-enable object-property-newline */
  }

  describe("Lockbox", function () {
    it("lp token properties should be derived from vault token", async function () {
      const {
        diamond, tier2, hyperFactory, routeFactory, mailbox, vaultToken, lpToken, vaultManager, owner,
      } = await loadFixture(deployHyperStaking);

      expect(await lpToken.name()).to.equal(await vaultToken.name());
      expect(await lpToken.symbol()).to.equal(await vaultToken.symbol());
      expect(await lpToken.decimals()).to.equal(await vaultToken.decimals());

      {
        const strangeToken = await shared.deloyTestERC20("Test 14 dec Coin", "t14c", 14);
        const reserveStrategy2 = await shared.createReserveStrategy(
          diamond, shared.nativeTokenAddress, await strangeToken.getAddress(), parseEther("1"),
        );

        const vname = "strange vault";
        const vsymbol = "sv";

        await mailbox.connect(owner).setFee(0n);
        await hyperFactory.connect(vaultManager).addStrategy(
          reserveStrategy2,
          vname,
          vsymbol,
          0n,
        );

        const tokens2 = await shared.getDerivedTokens(
          tier2, routeFactory, await reserveStrategy2.getAddress(),
        );

        expect(await tokens2.vaultToken.name()).to.equal(vname);
        expect(await tokens2.vaultToken.symbol()).to.equal(vsymbol);
        expect(await tokens2.vaultToken.decimals()).to.equal(14); // 14

        expect(await tokens2.lpToken.name()).to.equal(vname);
        expect(await tokens2.lpToken.symbol()).to.equal(vsymbol);
        expect(await tokens2.lpToken.decimals()).to.equal(14); // 14
      }
    });

    it("test origin update and acl", async function () {
      const { hyperlaneHandler, lockbox, lumiaFactoryManager } = await loadFixture(deployHyperStaking);

      await expect(hyperlaneHandler.setMailbox(lockbox)).to.be.reverted;

      // errors
      await expect(hyperlaneHandler.updateAuthorizedOrigin(
        ZeroAddress, true, 123,
      )).to.be.reverted;

      await expect(hyperlaneHandler.connect(lumiaFactoryManager).updateAuthorizedOrigin(
        ZeroAddress, true, 123,
      )).to.be.revertedWithCustomError(hyperlaneHandler, "OriginUpdateFailed");

      // events
      await expect(hyperlaneHandler.connect(lumiaFactoryManager).updateAuthorizedOrigin(
        lumiaFactoryManager, true, 123,
      ))
        .to.emit(hyperlaneHandler, "AuthorizedOriginUpdated")
        .withArgs(lumiaFactoryManager, true, 123);
    });

    it("stake deposit to tier2 with non-zero mailbox fee", async function () {
      const {
        deposit, tier1, reserveStrategy, vaultToken, lpToken, mailboxFee, owner, alice,
      } = await loadFixture(deployHyperStaking);

      const lpBefore = await lpToken.balanceOf(alice);

      const stakeAmount = parseEther("2");

      const tier2 = 2;
      await expect(deposit.stakeDepositTier2(
        reserveStrategy, stakeAmount, alice, { value: stakeAmount + mailboxFee },
      ))
        .to.emit(deposit, "StakeDeposit")
        .withArgs(owner, alice, reserveStrategy, stakeAmount, tier2);

      const lpAfter = await lpToken.balanceOf(alice);
      expect(lpAfter).to.be.gt(lpBefore);

      // more accurate amount calculation
      const allocation = await reserveStrategy.previewAllocation(stakeAmount);
      const lpAmount = await vaultToken.previewDeposit(allocation);

      expect(lpAfter).to.be.eq(lpBefore + lpAmount);

      // stake values should be 0 in tier1
      expect((await tier1.userTier1Info(reserveStrategy, alice)).stake).to.equal(0);
      expect((await tier1.vaultTier1Info(reserveStrategy)).totalStake).to.equal(0);
    });

    it("mailbox fee is needed when adding strategy too", async function () {
      const {
        diamond, hyperFactory, lockbox, mailboxFee, vaultManager,
      } = await loadFixture(deployHyperStaking);

      // new pool and strategy
      const asset2 = await shared.deloyTestERC20("Test Reserve Asset 2", "t2");

      const strategy2 = await shared.createReserveStrategy(
        diamond, shared.nativeTokenAddress, await asset2.getAddress(), parseEther("1"),
      );

      // revert if mailbox fee is not sent
      await expect(hyperFactory.connect(vaultManager).addStrategy(
        strategy2,
        "vault2",
        "v2",
        0n,
      )).to.be.reverted;

      expect( // in a real scenario fee could depend on the token address, correct name and symbol
        await lockbox.quoteDispatchTokenDeploy(ZeroAddress, "Test Reserve Asset 2", "t2", 18),
      ).to.equal(mailboxFee);

      await hyperFactory.connect(vaultManager).addStrategy(
        strategy2,
        "vault3",
        "v3",
        0n,
        { value: mailboxFee },
      );
    });

    it("redeem the should triger tier2 leave on the origin chain - non-zero mailbox fee", async function () {
      const {
        deposit, reserveStrategy, mailbox, vaultToken, hyperlaneHandler, routeFactory,
        testReserveAsset, lpToken, mailboxFee, reserveAssetPrice, alice,
      } = await loadFixture(deployHyperStaking);

      const stakeAmount = parseEther("3");
      const expectedLpAmount = stakeAmount * parseEther("1") / reserveAssetPrice;

      await expect(deposit.stakeDepositTier2(
        reserveStrategy, stakeAmount, alice, { value: stakeAmount + mailboxFee },
      ))
        .to.emit(routeFactory, "TokenBridged")
        .withArgs(reserveStrategy, lpToken, alice.address, expectedLpAmount);

      const lpAfter = await lpToken.balanceOf(alice);
      expect(lpAfter).to.eq(expectedLpAmount);

      await lpToken.connect(alice).approve(hyperlaneHandler, lpAfter);

      await expect(hyperlaneHandler.connect(alice).redeemLpTokensDispatch(
        reserveStrategy, alice, lpAfter,
      ))
        .to.be.revertedWithCustomError(mailbox, "DispatchUnderpaid");

      const dispatchFee = await hyperlaneHandler.quoteDispatchTokenRedeem(reserveStrategy, alice, lpAfter);

      await expect(hyperlaneHandler.redeemLpTokensDispatch(ZeroAddress, alice, lpAfter))
        .to.be.revertedWithCustomError(routeFactory, "RouteDoesNotExist")
        .withArgs(ZeroAddress);

      // redeem should return stakeAmount
      const redeemTx = hyperlaneHandler.connect(alice).redeemLpTokensDispatch(
        reserveStrategy, alice, lpAfter, { value: dispatchFee },
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
        strategy: ZeroAddress,
        name: "Test Token",
        symbol: "TT",
        decimals: 2,
        metadata: "0x1234",
      };

      const bytes1 = await testWrapper.serializeTokenDeploy(
        message1.strategy,
        message1.name,
        message1.symbol,
        message1.decimals,
        message1.metadata,
      );

      expect(await testWrapper.messageType(bytes1)).to.equal(0);
      expect(await testWrapper.strategy(bytes1)).to.equal(message1.strategy);
      expect(decodeString(await testWrapper.name(bytes1))).to.equal(message1.name);
      expect(decodeString(await testWrapper.symbol(bytes1))).to.equal(message1.symbol);
      expect(await testWrapper.tokenDeployMetadata(bytes1)).to.equal(message1.metadata);

      // TokenBridge

      const message2 = {
        strategy: ZeroAddress,
        sender: ZeroAddress,
        stake: parseEther("1"),
        shares: parseEther("0.9"),
        metadata: "0x1234",
      };

      const bytes2 = await testWrapper.serializeTokenBridge(
        message2.strategy,
        message2.sender,
        message2.stake,
        message2.shares,
        message2.metadata,
      );

      expect(await testWrapper.messageType(bytes2)).to.equal(1);
      expect(await testWrapper.strategy(bytes2)).to.equal(message2.strategy);
      expect(await testWrapper.sender(bytes2)).to.equal(message2.sender);
      expect(await testWrapper.stakeAmount(bytes2)).to.equal(message2.stake);
      expect(await testWrapper.sharesAmount(bytes2)).to.equal(message2.shares);
      expect(await testWrapper.tokenBridgeMetadata(bytes2)).to.equal(message2.metadata);

      // RouteRegister

      const messageRR = {
        strategy: ZeroAddress,
        rwaAsset: "0x0146109EC55EA184e0f8e6Ea06Ef6e5F45E2e804",
        metadata: "0x434a",
      };

      const bytesRR = await testWrapper.serializeRouteRegistry(
        messageRR.strategy,
        messageRR.rwaAsset,
        messageRR.metadata,
      );

      expect(await testWrapper.messageType(bytesRR)).to.equal(2);
      expect(await testWrapper.strategy(bytesRR)).to.equal(messageRR.strategy);
      expect(await testWrapper.rwaAsset(bytesRR)).to.equal(messageRR.rwaAsset);
      expect(await testWrapper.routeRegistryMetadata(bytesRR)).to.equal(messageRR.metadata);

      // StakeInfo

      const messageSI = {
        strategy: ZeroAddress,
        sender: ZeroAddress,
        stake: parseEther("4.04"),
        metadata: "0x1433",
      };

      const bytesSI = await testWrapper.serializeStakeInfo(
        messageSI.strategy,
        messageSI.sender,
        messageSI.stake,
        messageSI.metadata,
      );

      expect(await testWrapper.messageType(bytesSI)).to.equal(3);
      expect(await testWrapper.strategy(bytesSI)).to.equal(messageSI.strategy);
      expect(await testWrapper.sender(bytesSI)).to.equal(messageSI.sender);
      expect(await testWrapper.stakeAmount(bytesSI)).to.equal(messageSI.stake);
      expect(await testWrapper.stakeInfoMetadata(bytesSI)).to.equal(messageSI.metadata);

      // TokenRedeem

      const message5 = {
        strtegy: ZeroAddress,
        sender: ZeroAddress,
        amount: parseEther("2"),
        metadata: "0x1256",
      };

      const bytes5 = await testWrapper.serializeTokenRedeem(
        message5.strtegy,
        message5.sender,
        message5.amount,
        message5.metadata,
      );

      expect(await testWrapper.messageType(bytes5)).to.equal(4);
      expect(await testWrapper.strategy(bytes5)).to.equal(message5.strtegy);
      expect(await testWrapper.sender(bytes5)).to.equal(message5.sender);
      expect(await testWrapper.redeemAmount(bytes5)).to.equal(message5.amount);
      expect(await testWrapper.tokenRedeemMetadata(bytes5)).to.equal(message5.metadata);
    });

    it("string limitations", async function () {
      const testWrapper = await loadFixture(deployTestWrapper);

      const message = {
        strategy: ZeroAddress,
        name: "Test Token with a little longer name than usual, still working?",
        symbol: "TTSYMBOLEXTENDED 123456789",
        decimals: 15,
        metadata: "0x",
      };

      const bytes1 = await testWrapper.serializeTokenDeploy(
        message.strategy,
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
