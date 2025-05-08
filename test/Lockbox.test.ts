import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { parseEther, ZeroAddress } from "ethers";

import * as shared from "./shared";

import { RouteRegistryDataStruct } from "../typechain-types/contracts/hyperstaking/interfaces/IRouteRegistry";
import { StakeInfoDataStruct } from "../typechain-types/contracts/hyperstaking/interfaces/IStakeInfoRoute";
import { StakeRewardDataStruct } from "../typechain-types/contracts/hyperstaking/interfaces/IStakeRewardRoute";
import { StakeRedeemDataStruct } from "../typechain-types/contracts/lumia-diamond/interfaces/IStakeRedeemRoute";

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testReserveAsset = await shared.deloyTestERC20("Test Reserve Asset", "tRaETH");
  const erc4626Vault = await shared.deloyTestERC4626Vault(testReserveAsset);

  // -------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Apply Strategies --------------------

  // strategy asset price to eth 2:1
  const reserveAssetPrice = parseEther("2");

  const reserveStrategy = await shared.createReserveStrategy(
    hyperStaking.diamond, shared.nativeTokenAddress, await testReserveAsset.getAddress(), reserveAssetPrice,
  );

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    reserveStrategy,
    "reserve eth vault 1",
    "rETH1",
  );

  // set fee after strategy is added
  const mailboxFee = parseEther("0.05");
  await hyperStaking.mailbox.connect(signers.owner).setFee(mailboxFee);

  // -------------------- Hyperlane Handler --------------------

  const { principalToken, vaultShares } = await shared.getDerivedTokens(
    hyperStaking.hyperlaneHandler,
    await reserveStrategy.getAddress(),
  );

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    testReserveAsset, reserveStrategy, principalToken, vaultShares, // test contracts
    reserveAssetPrice, mailboxFee, // values
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

describe("Lockbox", function () {
  describe("Lockbox Facet", function () {
    it("vault token properties should be correct", async function () {
      const { hyperStaking, signers } = await loadFixture(deployHyperStaking);
      const { diamond, hyperFactory, mailbox } = hyperStaking;
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
      );

      const vault2 = await shared.getDerivedTokens(
        hyperStaking.hyperlaneHandler,
        await reserveStrategy2.getAddress(),
      );

      expect(await vault2.principalToken.name()).to.equal(`Principal ${vname}`);
      expect(await vault2.principalToken.symbol()).to.equal("p" + vsymbol);
      expect(await vault2.principalToken.decimals()).to.equal(14); // 14

      expect(await vault2.vaultShares.name()).to.equal(vname);
      expect(await vault2.vaultShares.symbol()).to.equal(vsymbol);
      expect(await vault2.vaultShares.decimals()).to.equal(14); // 14
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

    // TODO: do it with shares
    // it("stake deposit with non-zero mailbox fee", async function () {
    //   const { hyperStaking, reserveStrategy, vaultToken, lumiaAssetToken, mailboxFee, signers } = await loadFixture(deployHyperStaking);
    //   const { deposit } = hyperStaking;
    //   const { owner, alice } = signers;
    //
    //   const rwaBefore = await lumiaAssetToken.balanceOf(alice);
    //
    //   const stakeAmount = parseEther("2");
    //
    //   const depositType = 1;
    //   await expect(deposit.stakeDeposit(
    //     reserveStrategy, alice, stakeAmount, { value: stakeAmount + mailboxFee },
    //   ))
    //     .to.emit(deposit, "StakeDeposit")
    //     .withArgs(owner, alice, reserveStrategy, stakeAmount, depositType);
    //
    //   const rwaAfter = await rwaETH.balanceOf(alice);
    //   expect(rwaAfter).to.be.gt(rwaBefore);
    //   expect(rwaAfter).to.be.eq(stakeAmount);
    //
    //   // more accurate amount calculation
    //   const allocation = await reserveStrategy.previewAllocation(stakeAmount);
    //   const vaultShares = await vaultToken.previewDeposit(allocation);
    //
    //   expect(vaultShares).to.be.eq(await vaultToken.totalSupply());
    // });

    it("mailbox fee is needed when adding strategy too", async function () {
      const { hyperStaking, reserveStrategy, mailboxFee, signers } = await loadFixture(deployHyperStaking);
      const { diamond, hyperFactory, routeRegistry } = hyperStaking;
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
      )).to.be.reverted;

      expect( // in a real scenario fee could depend on the token address, correct name and symbol
        await routeRegistry.quoteDispatchRouteRegistry({
          strategy: reserveStrategy,
          name: "vault3",
          symbol: "v3",
          decimals: 18,
          metadata: "0x",
        } as RouteRegistryDataStruct)).to.equal(mailboxFee);

      await hyperFactory.connect(vaultManager).addStrategy(
        strategy2,
        "vault3",
        "v3",
        { value: mailboxFee },
      );
    });

    // TODO: when redeem is implemented
    // it("redeem the should triger leave on the origin chain - non-zero mailbox fee", async function () {
    //   const { hyperStaking, reserveStrategy, vaultToken, testReserveAsset, reserveAssetPrice, mailboxFee, signers } = await loadFixture(deployHyperStaking);
    //   const { deposit, hyperlaneHandler, realAssets, mailbox, rwaETH } = hyperStaking;
    //   const { alice } = signers;
    //
    //   const stakeAmount = parseEther("3");
    //   const expectedLpAmount = stakeAmount * parseEther("1") / reserveAssetPrice;
    //
    //   await expect(deposit.stakeDeposit(
    //     reserveStrategy, alice, stakeAmount, { value: stakeAmount + mailboxFee },
    //   ))
    //     .to.emit(realAssets, "RwaMint")
    //     .withArgs(reserveStrategy, rwaETH, alice.address, stakeAmount);
    //
    //   const rwaAfter = await rwaETH.balanceOf(alice);
    //   expect(rwaAfter).to.eq(stakeAmount);
    //
    //   await rwaETH.connect(alice).approve(realAssets, rwaAfter);
    //
    //   await expect(realAssets.connect(alice).handleRwaRedeem(
    //     reserveStrategy, alice, alice, rwaAfter,
    //   ))
    //     .to.be.revertedWithCustomError(mailbox, "DispatchUnderpaid");
    //
    //   const dispatchFee = await hyperlaneHandler.quoteDispatchStakeRedeem(reserveStrategy, alice, rwaAfter);
    //
    //   await expect(realAssets.handleRwaRedeem(ZeroAddress, alice, alice, rwaAfter))
    //     // custom error from LibInterchainFactory (unfortunetaly hardhat doesn't support it)
    //     // .to.be.revertedWithCustomError(realAssets, "RouteDoesNotExist")
    //     .to.be.reverted;
    //
    //   // redeem should return stakeAmount
    //   const redeemTx = realAssets.connect(alice).handleRwaRedeem(
    //     reserveStrategy, alice, alice, rwaAfter, { value: dispatchFee },
    //   );
    //
    //   // lpToken -> vaultAsset -> strategy allocation -> stake withdraw
    //   await expect(redeemTx).to.changeEtherBalance(alice, stakeAmount - dispatchFee);
    //   await expect(redeemTx).to.changeTokenBalance(testReserveAsset, vaultToken, -expectedLpAmount);
    //
    //   expect(await rwaETH.balanceOf(alice)).to.eq(0);
    // });
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

      // RouteRegister

      const messageRR: RouteRegistryDataStruct = {
        strategy: ZeroAddress,
        name: "Test Token",
        symbol: "TT",
        decimals: 2,
        metadata: "0x1234",
      };

      const bytesRR = await testWrapper.serializeRouteRegistry(messageRR);

      expect(await testWrapper.messageType(bytesRR)).to.equal(0);
      expect(await testWrapper.strategy(bytesRR)).to.equal(messageRR.strategy);
      expect(decodeString(await testWrapper.name(bytesRR))).to.equal(messageRR.name);
      expect(decodeString(await testWrapper.symbol(bytesRR))).to.equal(messageRR.symbol);
      expect(await testWrapper.routeRegistryMetadata(bytesRR)).to.equal(messageRR.metadata);

      // StakeInfo

      const messageSI: StakeInfoDataStruct = {
        strategy: "0x7846C5d815300D27c4975C93Fdbe19b9D352F0d3",
        sender: "0xE5326B17594A697B27F9807832A0CF7CB025B4bb",
        stake: parseEther("4.04"),
      };

      const bytesSI = await testWrapper.serializeStakeInfo(messageSI);

      expect(await testWrapper.messageType(bytesSI)).to.equal(1);
      expect(await testWrapper.strategy(bytesSI)).to.equal(messageSI.strategy);
      expect(await testWrapper.sender(bytesSI)).to.equal(messageSI.sender);
      expect(await testWrapper.stake(bytesSI)).to.equal(messageSI.stake);

      // StakeReward

      const messageRI: StakeRewardDataStruct = {
        strategy: "0x7846C5d815300D27c4975C93Fdbe19b9D352F0d3",
        stakeAdded: parseEther("1.11"),
      };

      const bytesRI = await testWrapper.serializeStakeReward(messageRI);

      expect(await testWrapper.messageType(bytesRI)).to.equal(2);
      expect(await testWrapper.strategy(bytesRI)).to.equal(messageRI.strategy);
      expect(await testWrapper.stakeAdded(bytesRI)).to.equal(messageRI.stakeAdded);

      // StakeRedeem

      const messageSR: StakeRedeemDataStruct = {
        strategy: "0x337baDc64C441e6956B87D248E5Bc284828cfa84",
        sender: "0xcb37D723BE930Fca39F46F019d84E1B359d2170C",
        redeemAmount: parseEther("2"),
      };

      const bytesSR = await testWrapper.serializeStakeRedeem(messageSR);

      expect(await testWrapper.messageType(bytesSR)).to.equal(3);
      expect(await testWrapper.strategy(bytesSR)).to.equal(messageSR.strategy);
      expect(await testWrapper.sender(bytesSR)).to.equal(messageSR.sender);
      expect(await testWrapper.redeemAmount(bytesSR)).to.equal(messageSR.redeemAmount);
    });
  });
});
