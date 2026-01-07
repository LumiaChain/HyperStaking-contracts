import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { parseEther, ZeroAddress } from "ethers";

import * as shared from "../shared";

import { StakeRedeemDataStruct } from "../../typechain-types/contracts/lumia-diamond/interfaces/IStakeRedeemRoute";
import { deployHyperStakingBase } from "../setup";

async function deployHyperStaking() {
  const {
    signers, hyperStaking, lumiaDiamond, testERC20, invariantChecker, mailbox,
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
  setGlobalInvariantChecker(invariantChecker);

  // -------------------- Hyperlane Handler --------------------

  const { principalToken, vaultShares } = await shared.getDerivedTokens(
    lumiaDiamond.hyperlaneHandler,
    await reserveStrategy.getAddress(),
  );

  /* eslint-disable object-property-newline */
  return {
    signers, // signers
    hyperStaking, lumiaDiamond, // HyperStaking deployment
    testERC20, reserveStrategy, principalToken, vaultShares, mailbox, // test contracts
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

      await expect(deposit.deposit(
        reserveStrategy, alice, stakeAmount, 0, { value: stakeAmount },
      ))
        .to.emit(deposit, "Deposit")
        .withArgs(owner, alice, reserveStrategy, stakeAmount, 0);

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

    it("reverts report when vault totalSupply is zero", async function () {
      const {
        hyperStaking, lumiaDiamond, reserveStrategy, signers, vaultShares,
      } = await loadFixture(deployHyperStaking);

      const { deposit, allocation } = hyperStaking;
      const { realAssets } = lumiaDiamond;
      const { alice, strategyManager, vaultManager } = signers;

      const initialDeposit = parseEther("10");

      // deposits native into the strategy
      await expect(deposit.connect(alice).deposit(reserveStrategy, alice, initialDeposit, 0, {
        value: initialDeposit,
      }))
        .to.emit(deposit, "Deposit");

      // double the asset price (2 -> 4)
      const assetPrice = await reserveStrategy.assetPrice();
      await reserveStrategy.connect(strategyManager).setAssetPrice(assetPrice * 2n);

      // Alice redeems all shares on Lumia side, then claims withdrawal
      const aliceShares = await vaultShares.balanceOf(alice);
      expect(aliceShares).to.equal(initialDeposit);

      await expect(realAssets.connect(alice).redeem(reserveStrategy, alice, alice, aliceShares))
        .to.emit(realAssets, "RwaRedeem");

      const lastClaimIdAlice = await shared.getLastClaimId(
        deposit,
        reserveStrategy,
        alice,
      );

      await shared.claimAtDeadline(deposit, lastClaimIdAlice, alice);

      // vault has zero shares
      expect(await vaultShares.totalSupply()).to.equal(0);

      // there is still some revenue to report from the strategy
      const expectedRevenue = await allocation.checkRevenue(reserveStrategy);
      expect(expectedRevenue).to.be.gt(0);

      await allocation.connect(vaultManager).setFeeRecipient(reserveStrategy, vaultManager);

      // report now must revert with custom error, because vault totalSupply == 0
      // covers ERC4626 edge-case, donation to empty shares vault
      await expect(
        allocation.connect(vaultManager).report(reserveStrategy),
      ).to.be.revertedWithCustomError(shared.errors, "RewardDonationZeroSupply");
    });

    it("shares should be minted equally regardless of the deposit order", async function () {
      const {
        signers, hyperStaking, reserveStrategy, vaultShares,
      } = await loadFixture(deployHyperStaking);
      const { deposit } = hyperStaking;
      const { owner, alice, bob } = signers;

      const stakeAmount = parseEther("7");

      await deposit.deposit(reserveStrategy, owner, stakeAmount, 0, { value: stakeAmount });
      await deposit.deposit(reserveStrategy, bob, stakeAmount, 0, { value: stakeAmount });
      await deposit.deposit(reserveStrategy, alice, stakeAmount, 0, { value: stakeAmount });

      const aliceShares = await vaultShares.balanceOf(alice);
      const bobShares = await vaultShares.balanceOf(bob);
      const ownerShares = await vaultShares.balanceOf(owner);

      expect(aliceShares).to.be.eq(bobShares);
      expect(aliceShares).to.be.eq(ownerShares);

      // 2x stake
      await deposit.deposit(reserveStrategy, alice, stakeAmount, 0, { value: stakeAmount });

      const aliceShares2 = await vaultShares.balanceOf(alice);
      expect(aliceShares2).to.be.eq(2n * bobShares);
    });

    it("it should be possible to redeem and withdraw stake", async function () {
      const {
        signers, hyperStaking, lumiaDiamond, testERC20, reserveStrategy, reserveAssetPrice, principalToken, vaultShares,
      } = await loadFixture(deployHyperStaking);
      const { deposit, lockbox } = hyperStaking;
      const { realAssets, stakeRedeemRoute } = lumiaDiamond;
      const { alice, bob } = signers;

      expect(await vaultShares.balanceOf(alice)).to.be.eq(0);

      const stakeAmount = parseEther("3");
      await deposit.deposit(reserveStrategy, alice, stakeAmount, 0, { value: stakeAmount });

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
      const stakeRedeemData: StakeRedeemDataStruct = {
        nonce: 1,
        strategy: reserveStrategy,
        user: alice,
        redeemAmount: stakeAmount,
      };
      const dispatchFee = await stakeRedeemRoute.quoteDispatchStakeRedeem(stakeRedeemData);

      await realAssets.connect(alice).redeem(
        reserveStrategy, alice, alice, stakeAmount, { value: dispatchFee },
      );

      // back to zero
      expect(await vaultShares.balanceOf(alice)).to.be.eq(0);
      expect(await principalToken.balanceOf(vaultShares)).to.be.eq(0);
      expect(await testERC20.balanceOf(lockbox)).to.be.eq(0);

      // -- scenario with approval redeem
      await deposit.deposit(reserveStrategy, alice, stakeAmount, 0, { value: stakeAmount });

      // alice withdraw for bob
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
      const { claimTx } = shared.claimAtDeadline(deposit, lastClaimId, bob);
      await expect(claimTx)
        .to.changeEtherBalance(bob, stakeAmount);

      expect(await testERC20.balanceOf(lockbox)).to.be.eq(0);
    });

    it("redeem flow: owner, receiver and third-party approvals", async function () {
      const {
        signers, hyperStaking, lumiaDiamond, reserveStrategy, vaultShares,
      } = await loadFixture(deployHyperStaking);

      const { deposit } = hyperStaking;
      const { realAssets } = lumiaDiamond;
      const { alice, bob } = signers;

      const stakeAmount = parseEther("3");
      await deposit.deposit(reserveStrategy, alice, stakeAmount, 0, {
        value: stakeAmount,
      });

      const oneShare = stakeAmount / 3n;

      // sanity check: no allowance set
      expect(await vaultShares.allowance(alice, realAssets)).to.eq(0);
      expect(await vaultShares.allowance(realAssets, vaultShares)).to.eq(0);

      // --- owner redeem: no approval, self receiver ---

      await expect(
        realAssets.connect(alice).redeem(
          reserveStrategy,
          alice, // from
          alice, // to
          oneShare,
        ),
      ).to.not.be.reverted;

      expect(await vaultShares.balanceOf(alice)).to.eq(stakeAmount - oneShare);

      // --- owner redeem: no approval, different receiver "to" ---

      await expect(
        realAssets.connect(alice).redeem(
          reserveStrategy,
          alice, // from
          bob,   // to
          oneShare,
        ),
      ).to.not.be.reverted;

      expect(await vaultShares.balanceOf(alice)).to.eq(stakeAmount - 2n * oneShare);

      // shares are burned, not transferred to bob
      expect(await vaultShares.balanceOf(bob)).to.eq(0);

      // --- third party redeem: requires approval from owner ---

      const remainingShares = await vaultShares.balanceOf(alice);
      expect(remainingShares).to.eq(oneShare);

      // no approval: bob cannot redeem alice shares
      await expect(
        realAssets.connect(bob).redeem(
          reserveStrategy,
          alice, // from
          bob,   // to
          remainingShares,
        ),
      ).to.be.reverted;

      // after approval: bob can redeem on behalf of alice
      await vaultShares.connect(alice).approve(bob, remainingShares);

      await expect(
        realAssets.connect(bob).redeem(
          reserveStrategy,
          alice, // from
          bob,   // to
          remainingShares,
        ),
      ).to.not.be.reverted;

      expect(await vaultShares.balanceOf(alice)).to.eq(0);
      expect(await vaultShares.balanceOf(bob)).to.eq(0);

      expect(await vaultShares.allowance(alice, bob)).to.eq(0);
      expect(await vaultShares.allowance(alice, realAssets)).to.eq(0);
      expect(await vaultShares.allowance(bob, realAssets)).to.eq(0);
      expect(await vaultShares.allowance(realAssets, vaultShares)).to.eq(0);
    });

    it("redeem: zero values validation - reverts", async function () {
      const {
        signers, hyperStaking, lumiaDiamond, reserveStrategy,
      } = await loadFixture(deployHyperStaking);

      const { deposit } = hyperStaking;
      const { realAssets, stakeRedeemRoute } = lumiaDiamond;
      const { alice } = signers;

      const stakeAmount = parseEther("1");
      await deposit.deposit(reserveStrategy, alice, stakeAmount, 0, { value: stakeAmount });

      const redeemAmount = parseEther("0.1");
      const dispatchFee = await stakeRedeemRoute.quoteDispatchStakeRedeem({
        nonce: 1,
        strategy: reserveStrategy,
        user: alice,
        redeemAmount,
      });

      // zero amount
      await expect(
        realAssets.connect(alice).redeem(reserveStrategy, alice, alice, 0n),
      ).to.be.revertedWithCustomError(shared.errors, "ZeroAmount");

      // zero strategy
      await expect(
        realAssets.connect(alice).redeem(ZeroAddress, alice, alice, redeemAmount, {
          value: dispatchFee,
        }),
      ).to.be.revertedWithCustomError(shared.errors, "ZeroAddress");

      // zero owner
      await expect(
        realAssets.connect(alice).redeem(reserveStrategy, ZeroAddress, alice, redeemAmount, {
          value: dispatchFee,
        }),
      ).to.be.revertedWithCustomError(shared.errors, "ZeroAddress");

      // zero receiver
      await expect(
        realAssets.connect(alice).redeem(reserveStrategy, alice, ZeroAddress, redeemAmount, {
          value: dispatchFee,
        }),
      ).to.be.revertedWithCustomError(shared.errors, "ZeroAddress");
    });
  });

  it("replay protection: should reject replayed StakeInfo and StakeRedeem after mailbox rotation", async function () {
    const {
      signers, hyperStaking, lumiaDiamond, mailbox, reserveStrategy, vaultShares,
    } = await loadFixture(deployHyperStaking);

    const { deposit, lockbox } = hyperStaking;
    const { hyperlaneHandler, realAssets } = lumiaDiamond;
    const { vaultManager, lumiaFactoryManager, alice } = signers;

    // ---------- Helper: build Hyperlane message bytes ----------
    const buildMessage = async (
      originDomain: number,
      destinationDomain: number,
      senderAddr: string,
      recipientAddr: string,
      body: string,
      mailboxNonce = 123,
    ) => {
      return ethers.solidityPacked(
        ["uint8", "uint32", "uint32", "bytes32", "uint32", "bytes32", "bytes"],
        [
          33,
          mailboxNonce,
          originDomain,
          ethers.zeroPadValue(senderAddr, 32),
          destinationDomain,
          ethers.zeroPadValue(recipientAddr, 32),
          body,
        ],
      );
    };

    // in the one-chain setup, origin == destination == mailbox.localDomain()
    const domain = Number(await mailbox.localDomain());

    // ============================================================
    // 1) Deposit direction: replay StakeInfo into HyperlaneHandler
    // ============================================================

    const stakeAmount = parseEther("1");
    await deposit.connect(alice).deposit(reserveStrategy, alice, stakeAmount, 0, { value: stakeAmount });

    const lastToLumia = await hyperlaneHandler.lastMessage();
    expect(lastToLumia.sender).to.eq(await lockbox.getAddress());

    const shares = await vaultShares.balanceOf(alice);
    await realAssets.connect(alice).redeem(reserveStrategy, alice, alice, shares);

    const lastToOrigin = (await lockbox.lockboxData()).lastMessage;
    expect(lastToOrigin.sender).to.eq(await hyperlaneHandler.getAddress());

    // rotate mailbox on Lumia side
    const newMailbox = await ethers.deployContract("OneChainMailbox", [0n, domain]);
    await newMailbox.waitForDeployment();

    // update mailbox address in hyperlaneHandler
    await hyperlaneHandler.connect(lumiaFactoryManager).setMailbox(newMailbox);

    // now try to deliver the exact same payload again via the NEW mailbox
    const replayStakeInfoMsg = await buildMessage(
      domain,
      domain,
      await lockbox.getAddress(),           // sender bytes32 must be lockbox
      await hyperlaneHandler.getAddress(),  // recipient is handler
      lastToLumia.data,                     // exact same body (incl nonce)
      777,
    );

    await expect(
      newMailbox.process("0x", replayStakeInfoMsg),
    ).to.be.revertedWithCustomError(shared.errors, "HyperlaneReplay");

    // ============================================================
    // 2) Redeem direction: replay StakeRedeem into LockboxFacet
    // ============================================================

    // lockbox uses propose/apply delay in your suite
    const DELAY = 60 * 60 * 24;
    await lockbox.connect(vaultManager).proposeMailbox(newMailbox);
    await time.increase(DELAY + 1);
    await lockbox.connect(vaultManager).applyMailbox();

    // replay same StakeRedeem body into lockbox via NEW mailbox
    const replayStakeRedeemMsg = await buildMessage(
      domain,
      domain,
      await hyperlaneHandler.getAddress(), // sender bytes32 must be handler
      await lockbox.getAddress(),          // recipient is lockbox
      lastToOrigin.data,                   // exact same body (incl nonce)
      888,
    );

    await expect(
      newMailbox.process("0x", replayStakeRedeemMsg),
    ).to.be.revertedWithCustomError(shared.errors, "HyperlaneReplay");
  });
});
