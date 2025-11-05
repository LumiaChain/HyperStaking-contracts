import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { parseEther, ZeroAddress } from "ethers";

import * as shared from "../shared";

import { StakeRedeemDataStruct } from "../../typechain-types/contracts/lumia-diamond/interfaces/IStakeRedeemRoute";
import { deployHyperStakingBase } from "../setup";

async function deployHyperStaking() {
  const {
    signers, hyperStaking, lumiaDiamond, testERC20, invariantChecker, defaultWithdrawDelay,
  } = await loadFixture(deployHyperStakingBase);

  // -------------------- Apply Strategies --------------------

  // strategy asset price to eth 2:1
  const reserveAssetPrice = parseEther("2");

  const reserveStrategy = await shared.createReserveStrategy(
    hyperStaking.diamond, shared.nativeTokenAddress, await testERC20.getAddress(), reserveAssetPrice,
  );

  const vaultSharesName = "eth vault1";
  const vaultSharesSymbol = "vETH1";

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    reserveStrategy,
    vaultSharesName,
    vaultSharesSymbol,
  );

  // -------------------- Setup Checker --------------------

  await invariantChecker.addStrategy(await reserveStrategy.getAddress());
  setInvChecker(invariantChecker);

  // -------------------- Hyperlane Handler --------------------

  const { principalToken, vaultShares } = await shared.getDerivedTokens(
    lumiaDiamond.hyperlaneHandler,
    await reserveStrategy.getAddress(),
  );

  /* eslint-disable object-property-newline */
  return {
    signers, // signers
    hyperStaking, lumiaDiamond, // HyperStaking deployment
    defaultWithdrawDelay,
    testERC20, reserveStrategy, principalToken, vaultShares, // test contracts
    reserveAssetPrice, vaultSharesName, vaultSharesSymbol, // values
  };
  /* eslint-enable object-property-newline */
}

describe("VaultShares", function () {
  afterEach(async () => {
    const c = globalThis.$invChecker;
    if (c) await c.check();
  });

  describe("InterchainFactory", function () {
    it("vault token name, symbol and decimals", async function () {
      const {
        signers, hyperStaking, lumiaDiamond, testERC20, reserveAssetPrice, principalToken, vaultShares, vaultSharesName, vaultSharesSymbol,
      } = await loadFixture(deployHyperStaking);

      const { diamond, hyperFactory } = hyperStaking;
      const { hyperlaneHandler } = lumiaDiamond;
      const { vaultManager } = signers;

      expect(await principalToken.name()).to.equal(`Principal ${vaultSharesName}`);
      expect(await principalToken.symbol()).to.equal("p" + vaultSharesSymbol);
      expect(await principalToken.decimals()).to.equal(18);

      expect(await vaultShares.name()).to.equal(vaultSharesName);
      expect(await vaultShares.symbol()).to.equal(vaultSharesSymbol);
      expect(await vaultShares.decimals()).to.equal(18);

      const testReserveAssetDecimals = await testERC20.decimals();

      // 18 - native token decimals
      expect(testReserveAssetDecimals).to.equal(18);
      expect(testReserveAssetDecimals).to.equal(await principalToken.decimals());
      expect(testReserveAssetDecimals).to.equal(await vaultShares.decimals());

      // create another vault shares to check different values

      const strangeDecimals = 11;
      const strangeUSDStake = await shared.deployTestERC20("Test USD Strange Asset", "tUSSA", strangeDecimals);

      const strangeStrategy = await shared.createReserveStrategy(
        diamond, await strangeUSDStake.getAddress(), await testERC20.getAddress(), reserveAssetPrice,
      );

      const vaultSharesName2 = "strange usd vault";
      const vaultSharesSymbol2 = "vUSSA";
      await hyperFactory.connect(vaultManager).addStrategy(
        strangeStrategy,
        vaultSharesName2,
        vaultSharesSymbol2,
      );

      const strangeLumiaTokens = await shared.getDerivedTokens(
        hyperlaneHandler,
        await strangeStrategy.getAddress(),
      );

      expect(await strangeLumiaTokens.principalToken.name()).to.equal(`Principal ${vaultSharesName2}`);
      expect(await strangeLumiaTokens.principalToken.symbol()).to.equal("p" + vaultSharesSymbol2);
      expect(await strangeLumiaTokens.principalToken.decimals()).to.equal(strangeDecimals);

      expect(await strangeLumiaTokens.vaultShares.name()).to.equal(vaultSharesName2);
      expect(await strangeLumiaTokens.vaultShares.symbol()).to.equal(vaultSharesSymbol2);
      expect(await strangeLumiaTokens.vaultShares.decimals()).to.equal(strangeDecimals);
    });

    it("test route and registration", async function () {
      const {
        signers, hyperStaking, lumiaDiamond, reserveStrategy,
      } = await loadFixture(deployHyperStaking);
      const { diamond, hyperFactory } = hyperStaking;
      const { hyperlaneHandler } = lumiaDiamond;
      const { vaultManager } = signers;

      const testAsset2 = await shared.deployTestERC20("Test Asset2", "tRaETH2");
      const testAsset3 = await shared.deployTestERC20("Test Asset3", "tRaETH3");

      const reserveStrategy2 = await shared.createReserveStrategy(
        diamond, shared.nativeTokenAddress, await testAsset2.getAddress(), parseEther("2"),
      );
      const reserveStrategy3 = await shared.createReserveStrategy(
        diamond, shared.nativeTokenAddress, await testAsset3.getAddress(), parseEther("3"),
      );

      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy2)).exists).to.equal(false);
      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy3)).exists).to.equal(false);

      // by adding new stategies more vault tokens should be created
      await hyperFactory.connect(vaultManager).addStrategy(
        reserveStrategy2,
        "eth vault2",
        "vETH2",
      );

      await hyperFactory.connect(vaultManager).addStrategy(
        reserveStrategy3,
        "eth vault3",
        "vETH3",
      );

      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy)).exists).to.equal(true);
      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy)).assetToken).to.not.equal(ZeroAddress);

      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy2)).exists).to.equal(true);
      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy2)).assetToken).to.not.equal(ZeroAddress);

      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy3)).exists).to.equal(true);
      expect((await hyperlaneHandler.getRouteInfo(reserveStrategy3)).assetToken).to.not.equal(ZeroAddress);
    });
  });

  describe("Allocation", function () {
    it("it shouldn't be possible to mint shares apart from the diamond", async function () {
      const { principalToken, vaultShares, signers } = await loadFixture(deployHyperStaking);
      const { alice } = signers;

      await expect(principalToken.mint(alice, 100))
        .to.be.revertedWithCustomError(vaultShares, "OwnableUnauthorizedAccount");

      await expect(vaultShares.deposit(100, alice))
        .to.be.revertedWithCustomError(vaultShares, "OwnableUnauthorizedAccount");

      await expect(vaultShares.mint(100, alice))
        .to.be.revertedWithCustomError(vaultShares, "OwnableUnauthorizedAccount");
    });

    it("stake deposit should generate vault shares", async function () {
      const {
        hyperStaking, reserveStrategy, principalToken, vaultShares, signers,
      } = await loadFixture(deployHyperStaking);
      const { deposit, allocation } = hyperStaking;
      const { owner, vaultManager, strategyManager, alice } = signers;

      const stakeAmount = parseEther("6");

      await expect(deposit.stakeDeposit(
        reserveStrategy, alice, stakeAmount, { value: stakeAmount },
      ))
        .to.emit(deposit, "StakeDeposit")
        .withArgs(owner, alice, reserveStrategy, stakeAmount);

      // both principalToken and shares should be minted in ration 1:1 to the stake at start
      expect(await vaultShares.totalSupply()).to.be.eq(stakeAmount);
      expect(await principalToken.totalSupply()).to.be.eq(stakeAmount);

      // simulate yield generation, increase asset price
      const assetPrice = await reserveStrategy.assetPrice();
      await reserveStrategy.connect(strategyManager).setAssetPrice(assetPrice * 2n);

      // compound stake
      const feeRecipient = vaultManager;
      await allocation.connect(vaultManager).setFeeRecipient(reserveStrategy, feeRecipient);
      await allocation.connect(vaultManager).report(reserveStrategy);

      // amount of shares stays the same
      expect(await vaultShares.totalSupply()).to.be.eq(stakeAmount);

      // principalToken amount should be increased
      const totalStake = (await allocation.stakeInfo(reserveStrategy)).totalStake;
      expect(await vaultShares.totalAssets()).to.be.eq(totalStake);
    });

    it("shares should be minted equally regardless of the deposit order", async function () {
      const {
        signers, hyperStaking, reserveStrategy, vaultShares,
      } = await loadFixture(deployHyperStaking);
      const { deposit } = hyperStaking;
      const { owner, alice, bob } = signers;

      const stakeAmount = parseEther("7");

      await deposit.stakeDeposit(reserveStrategy, owner, stakeAmount, { value: stakeAmount });
      await deposit.stakeDeposit(reserveStrategy, bob, stakeAmount, { value: stakeAmount });
      await deposit.stakeDeposit(reserveStrategy, alice, stakeAmount, { value: stakeAmount });

      const aliceShares = await vaultShares.balanceOf(alice);
      const bobShares = await vaultShares.balanceOf(bob);
      const ownerShares = await vaultShares.balanceOf(owner);

      expect(aliceShares).to.be.eq(bobShares);
      expect(aliceShares).to.be.eq(ownerShares);

      // 2x stake
      await deposit.stakeDeposit(reserveStrategy, alice, stakeAmount, { value: stakeAmount });

      const aliceShares2 = await vaultShares.balanceOf(alice);
      expect(aliceShares2).to.be.eq(2n * bobShares);
    });

    it("it should be possible to redeem and withdraw stake", async function () {
      const {
        signers, hyperStaking, lumiaDiamond, testERC20, reserveStrategy, reserveAssetPrice, principalToken, vaultShares, defaultWithdrawDelay,
      } = await loadFixture(deployHyperStaking);
      const { deposit, lockbox } = hyperStaking;
      const { realAssets, stakeRedeemRoute } = lumiaDiamond;
      const { alice, bob } = signers;

      expect(await vaultShares.balanceOf(alice)).to.be.eq(0);

      const stakeAmount = parseEther("3");
      await deposit.stakeDeposit(reserveStrategy, alice, stakeAmount, { value: stakeAmount });

      expect(await principalToken.totalSupply()).to.be.eq(stakeAmount); // 1:1 bridge mint
      expect(await principalToken.balanceOf(vaultShares)).to.be.eq(stakeAmount); // locked in vault

      expect(await vaultShares.totalAssets()).to.be.eq(stakeAmount);

      // check allocation
      const expectedAllocation = stakeAmount * parseEther("1") / reserveAssetPrice;
      expect(await testERC20.balanceOf(lockbox)).to.be.eq(expectedAllocation);

      // redeem should be possible only through realAssets facet - lumia proxy
      await expect(vaultShares.connect(alice).redeem(stakeAmount, alice, alice))
        .to.be.revertedWithCustomError(vaultShares, "OwnableUnauthorizedAccount");

      // withdraw should be possible only through realAssets facet - lumia proxy
      await expect(vaultShares.connect(alice).withdraw(stakeAmount, alice, alice))
        .to.be.revertedWithCustomError(vaultShares, "OwnableUnauthorizedAccount");

      // interchain redeem
      await vaultShares.connect(alice).approve(realAssets, stakeAmount);

      const stakeRedeemData: StakeRedeemDataStruct = {
        strategy: reserveStrategy,
        sender: alice,
        redeemAmount: stakeAmount,
      };
      const dispatchFee = await stakeRedeemRoute.quoteDispatchStakeRedeem(stakeRedeemData);

      await vaultShares.connect(alice).approve(realAssets, stakeAmount);
      await realAssets.connect(alice).redeem(
        reserveStrategy, alice, alice, stakeAmount, { value: dispatchFee },
      );

      // back to zero
      expect(await vaultShares.balanceOf(alice)).to.be.eq(0);
      expect(await principalToken.balanceOf(vaultShares)).to.be.eq(0);
      expect(await testERC20.balanceOf(lockbox)).to.be.eq(0);

      // -- scenario with approval redeem
      await deposit.stakeDeposit(reserveStrategy, alice, stakeAmount, { value: stakeAmount });

      // alice withdraw for bob
      await vaultShares.connect(alice).approve(realAssets, stakeAmount);
      const expectedUnlock = await shared.getCurrentBlockTimestamp() + defaultWithdrawDelay;

      await expect(realAssets.connect(alice).redeem(
        reserveStrategy, alice, bob, stakeAmount, { value: dispatchFee },
      )).to.changeTokenBalances(testERC20,
        [lockbox, reserveStrategy],
        [-expectedAllocation, expectedAllocation],
      );

      expect(await vaultShares.allowance(alice, bob)).to.be.eq(0);
      expect(await vaultShares.balanceOf(alice)).to.be.eq(0);
      expect(await vaultShares.balanceOf(bob)).to.be.eq(0);

      const lastClaimId = await shared.getLastClaimId(deposit, reserveStrategy, bob);
      await time.setNextBlockTimestamp(expectedUnlock);
      await expect(deposit.connect(bob).claimWithdraws([lastClaimId], bob))
        .to.changeEtherBalance(bob, stakeAmount);

      expect(await testERC20.balanceOf(lockbox)).to.be.eq(0);
    });
  });
});
