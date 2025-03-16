import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { parseEther, ZeroAddress } from "ethers";

import * as shared from "./shared";

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testReserveAsset = await shared.deloyTestERC20("Test Reserve Asset", "tRaETH");
  const erc4626Vault = await shared.deloyTestERC4626Vault(testReserveAsset);

  // -------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Apply Strategies --------------------

  const defaultRevenueFee = parseEther("0"); // 0% fee

  // strategy asset price to eth 2:1
  const reserveAssetPrice = parseEther("2");

  const reserveStrategy = await shared.createReserveStrategy(
    hyperStaking.diamond, shared.nativeTokenAddress, await testReserveAsset.getAddress(), reserveAssetPrice,
  );

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    reserveStrategy,
    "reserve eth vault 1",
    "rETH1",
    defaultRevenueFee,
    hyperStaking.rwaETH,
  );

  // set fee after strategy is added
  const mailboxFee = parseEther("0.05");
  await hyperStaking.mailbox.connect(signers.owner).setFee(mailboxFee);

  const vaultTokenAddress = (await hyperStaking.tier2.tier2Info(reserveStrategy)).vaultToken;
  const vaultToken = await ethers.getContractAt("VaultToken", vaultTokenAddress);

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    testReserveAsset, reserveStrategy, vaultToken, // test contracts
    defaultRevenueFee, reserveAssetPrice, mailboxFee, // values
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

describe("Lockbox", function () {
  describe("Lockbox Facet", function () {
    it("vault token properties should be correct", async function () {
      const { hyperStaking, signers } = await loadFixture(deployHyperStaking);
      const { diamond, tier2, hyperFactory, mailbox, rwaETH } = hyperStaking;
      const { owner, vaultManager } = signers;

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
        rwaETH,
      );

      const vault2Address = (await tier2.tier2Info(reserveStrategy2)).vaultToken;
      const vault2Token = await ethers.getContractAt("VaultToken", vault2Address);

      expect(await vault2Token.name()).to.equal(vname);
      expect(await vault2Token.symbol()).to.equal(vsymbol);
      expect(await vault2Token.decimals()).to.equal(14); // 14
    });

    it("test origin update and acl", async function () {
      const { hyperStaking, signers } = await loadFixture(deployHyperStaking);
      const { hyperlaneHandler, lockbox } = hyperStaking;
      const { lumiaFactoryManager } = signers;

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
      const { hyperStaking, reserveStrategy, vaultToken, mailboxFee, signers } = await loadFixture(deployHyperStaking);
      const { deposit, tier1, rwaETH } = hyperStaking;
      const { owner, alice } = signers;

      const rwaBefore = await rwaETH.balanceOf(alice);

      const stakeAmount = parseEther("2");

      const tier2 = 2;
      await expect(deposit.stakeDepositTier2(
        reserveStrategy, stakeAmount, alice, { value: stakeAmount + mailboxFee },
      ))
        .to.emit(deposit, "StakeDeposit")
        .withArgs(owner, alice, reserveStrategy, stakeAmount, tier2);

      const rwaAfter = await rwaETH.balanceOf(alice);
      expect(rwaAfter).to.be.gt(rwaBefore);
      expect(rwaAfter).to.be.eq(stakeAmount);

      // more accurate amount calculation
      const allocation = await reserveStrategy.previewAllocation(stakeAmount);
      const vaultShares = await vaultToken.previewDeposit(allocation);

      expect(vaultShares).to.be.eq(await vaultToken.totalSupply());

      // stake values should be 0 in tier1
      expect((await tier1.userTier1Info(reserveStrategy, alice)).stake).to.equal(0);
      expect((await tier1.tier1Info(reserveStrategy)).totalStake).to.equal(0);
    });

    it("mailbox fee is needed when adding strategy too", async function () {
      const { hyperStaking, mailboxFee, signers } = await loadFixture(deployHyperStaking);
      const { diamond, hyperFactory, lockbox, rwaETH } = hyperStaking;
      const { vaultManager } = signers;

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
        rwaETH,
      )).to.be.reverted;

      expect( // in a real scenario fee could depend on the token address, correct name and symbol
        await lockbox.quoteDispatchRouteRegistry(ZeroAddress, rwaETH),
      ).to.equal(mailboxFee);

      await hyperFactory.connect(vaultManager).addStrategy(
        strategy2,
        "vault3",
        "v3",
        0n,
        rwaETH,
        { value: mailboxFee },
      );
    });

    it("redeem the should triger tier2 leave on the origin chain - non-zero mailbox fee", async function () {
      const { hyperStaking, reserveStrategy, vaultToken, testReserveAsset, reserveAssetPrice, mailboxFee, signers } = await loadFixture(deployHyperStaking);
      const { deposit, hyperlaneHandler, realAssets, mailbox, rwaETH } = hyperStaking;
      const { alice } = signers;

      const stakeAmount = parseEther("3");
      const expectedLpAmount = stakeAmount * parseEther("1") / reserveAssetPrice;

      await expect(deposit.stakeDepositTier2(
        reserveStrategy, stakeAmount, alice, { value: stakeAmount + mailboxFee },
      ))
        .to.emit(realAssets, "RwaMint")
        .withArgs(reserveStrategy, rwaETH, alice.address, stakeAmount);

      const rwaAfter = await rwaETH.balanceOf(alice);
      expect(rwaAfter).to.eq(stakeAmount);

      await rwaETH.connect(alice).approve(realAssets, rwaAfter);

      await expect(realAssets.connect(alice).handleRwaRedeem(
        reserveStrategy, alice, alice, rwaAfter,
      ))
        .to.be.revertedWithCustomError(mailbox, "DispatchUnderpaid");

      const dispatchFee = await hyperlaneHandler.quoteDispatchStakeRedeem(reserveStrategy, alice, rwaAfter);

      await expect(realAssets.handleRwaRedeem(ZeroAddress, alice, alice, rwaAfter))
        // custom error from LibInterchainFactory (unfortunetaly hardhat doesn't support it)
        // .to.be.revertedWithCustomError(realAssets, "RouteDoesNotExist")
        .to.be.reverted;

      // redeem should return stakeAmount
      const redeemTx = realAssets.connect(alice).handleRwaRedeem(
        reserveStrategy, alice, alice, rwaAfter, { value: dispatchFee },
      );

      // lpToken -> vaultAsset -> strategy allocation -> stake withdraw
      await expect(redeemTx).to.changeEtherBalance(alice, stakeAmount - dispatchFee);
      await expect(redeemTx).to.changeTokenBalance(testReserveAsset, vaultToken, -expectedLpAmount);

      expect(await rwaETH.balanceOf(alice)).to.eq(0);
    });
  });

  describe("Hyperlane Mailbox Messages", function () {
    async function deployTestWrapper() {
      return await ethers.deployContract("TestHyperlaneMessages", []);
    }

    it("serialization and deserialization", async function () {
      const testWrapper = await loadFixture(deployTestWrapper);

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

      expect(await testWrapper.messageType(bytesRR)).to.equal(0);
      expect(await testWrapper.strategy(bytesRR)).to.equal(messageRR.strategy);
      expect(await testWrapper.rwaAsset(bytesRR)).to.equal(messageRR.rwaAsset);
      expect(await testWrapper.routeRegistryMetadata(bytesRR)).to.equal(messageRR.metadata);

      // StakeInfo

      const messageSI = {
        strategy: "0x7846C5d815300D27c4975C93Fdbe19b9D352F0d3",
        sender: "0xE5326B17594A697B27F9807832A0CF7CB025B4bb",
        stake: parseEther("4.04"),
      };

      const bytesSI = await testWrapper.serializeStakeInfo(
        messageSI.strategy,
        messageSI.sender,
        messageSI.stake,
      );

      expect(await testWrapper.messageType(bytesSI)).to.equal(1);
      expect(await testWrapper.strategy(bytesSI)).to.equal(messageSI.strategy);
      expect(await testWrapper.sender(bytesSI)).to.equal(messageSI.sender);
      expect(await testWrapper.stakeAmount(bytesSI)).to.equal(messageSI.stake);

      // MigrationInfo

      const messageMI = {
        fromStrategy: "0x6df9a4Bf32A9707C9E1D72fD39d4EcFc4D0Da3C7",
        toStrategy: "0x2edF86433A81797820B986e88E264C3562d5eF20",
        migrationAmount: parseEther("2.04"),
      };

      const bytesMI = await testWrapper.serializeMigrationInfo(
        messageMI.fromStrategy,
        messageMI.toStrategy,
        messageMI.migrationAmount,
      );

      expect(await testWrapper.messageType(bytesMI)).to.equal(2);
      expect(await testWrapper.fromStrategy(bytesMI)).to.equal(messageMI.fromStrategy);
      expect(await testWrapper.toStrategy(bytesMI)).to.equal(messageMI.toStrategy);
      expect(await testWrapper.migrationAmount(bytesMI)).to.equal(messageMI.migrationAmount);

      // StakeRedeem

      const messageSR = {
        strtegy: "0x337baDc64C441e6956B87D248E5Bc284828cfa84",
        sender: "0xcb37D723BE930Fca39F46F019d84E1B359d2170C",
        amount: parseEther("2"),
      };

      const bytesSR = await testWrapper.serializeStakeRedeem(
        messageSR.strtegy,
        messageSR.sender,
        messageSR.amount,
      );

      expect(await testWrapper.messageType(bytesSR)).to.equal(3);
      expect(await testWrapper.strategy(bytesSR)).to.equal(messageSR.strtegy);
      expect(await testWrapper.sender(bytesSR)).to.equal(messageSR.sender);
      expect(await testWrapper.redeemAmount(bytesSR)).to.equal(messageSR.amount);
    });
  });
});
