import { expect } from "chai";
import { ethers, ignition } from "hardhat";
import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { parseUnits, Log, Contract, ZeroAddress, parseEther } from "ethers";
import * as shared from "../shared";
import { TokenDetailsStruct } from "../../typechain-types/contracts/external/aera/Provisioner";
import { AeraConfigStruct } from "../../typechain-types/contracts/hyperstaking/strategies/GauntletStrategy";
import GauntletMockModule from "../../ignition/modules/test/GauntletMock";
import GauntletStrategyModule from "../../ignition/modules/GauntletStrategy";

async function getMockedGauntlet(testUSDC?: Contract) {
  const [owner, feeRecipient, alice, bob] = await ethers.getSigners();

  if (!testUSDC) {
    // deploy a test USDC
    testUSDC = await shared.deployTestERC20("Test USD Coin", "tUSDC", 6);
    await testUSDC.mint(alice.address, parseUnits("1000000", 6));
    await testUSDC.mint(bob.address, parseUnits("1000000", 6));
  }

  // --------------------

  const {
    aeraProvisioner, aeraPriceAndFeeCalculator, aeraMultiDepositorVault,
  } = await ignition.deploy(GauntletMockModule, {
    parameters: {
      GauntletMockModule: {
        usdcAddress: await testUSDC.getAddress(),
      },
    },
  });

  // -------------------- config

  // register vault in the PriceAndFeeCalculator (idempotent)
  await aeraPriceAndFeeCalculator.connect(owner).registerVault();

  // set thresholds and initial price so pricing is "active"
  await aeraPriceAndFeeCalculator.connect(owner).setThresholds(
    await aeraMultiDepositorVault.getAddress(),
    0,          // minPriceToleranceBps
    20_000,     // maxPriceToleranceBps (200%) to be safe for tests
    0,          // minUpdateInterval (disable for tests)
    120,        // maxPriceAge seconds (1 day) – or whatever your API expects
    30,         // maxUpdateDelayDays (lib-dependent; keep permissive)
  );

  // set initial unit price to 1 USDC per unit
  await aeraPriceAndFeeCalculator.connect(owner).setInitialPrice(
    await aeraMultiDepositorVault.getAddress(),
    parseUnits("1", 6), // unit price in numeraire (USDC has 6 decimals)
    await shared.getCurrentBlockTimestamp(),
  );

  // enable async deposits for USDC
  await aeraProvisioner.connect(owner).setTokenDetails(await testUSDC.getAddress(), {
    asyncDepositEnabled: true,
    asyncRedeemEnabled: true,
    syncDepositEnabled: false,
    depositMultiplier: 10_000,
    redeemMultiplier: 10_000,
  } as TokenDetailsStruct);

  return {
    owner, feeRecipient, alice, testUSDC, aeraProvisioner, aeraPriceAndFeeCalculator, aeraMultiDepositorVault,
  };
}

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // --------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n);

  // --------------------- Aera Mock --------------------

  const getMockedGauntletWithUSDC = () => getMockedGauntlet(hyperStaking.testUSDC);
  const aeraMock = await loadFixture(getMockedGauntletWithUSDC);

  // -------------------- Apply Strategy --------------------

  const { gauntletStrategy } = await ignition.deploy(GauntletStrategyModule, {
    parameters: {
      GauntletStrategyModule: {
        diamond: await hyperStaking.diamond.getAddress(),
        stakeToken: await hyperStaking.testUSDC.getAddress(),
        aeraProvisioner: await aeraMock.aeraProvisioner.getAddress(),
      },
    },
  });

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    gauntletStrategy,
    "gtUSTa vault",
    "lgtUSTa",
  );

  // set 0 slippage for tests, to simplify calculations
  const defaultConfig = await gauntletStrategy.aeraConfig();
  await gauntletStrategy.connect(signers.strategyManager).setAeraConfig({
    solverTip: defaultConfig.solverTip,
    deadlineOffset: defaultConfig.deadlineOffset,
    maxPriceAge: defaultConfig.maxPriceAge,
    slippageBps: 0,
    isFixedPrice: defaultConfig.isFixedPrice,
  } as AeraConfigStruct);

  // -------------------- Hyperlane Handler --------------------

  const { principalToken, vaultShares } = await shared.getDerivedTokens(
    hyperStaking.hyperlaneHandler,
    await gauntletStrategy.getAddress(),
  );

  // ----------------------------------------

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, aeraMock, gauntletStrategy, // contracts
    principalToken, vaultShares, // test contracts
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

describe("Aera", function () {
  describe("GauntletMock", function () {
    it("mock deployment setup test", async () => {
      const {
        owner,
        alice,
        testUSDC,
        aeraProvisioner,
        aeraPriceAndFeeCalculator,
        aeraMultiDepositorVault,
      } = await getMockedGauntlet();

      // sanity checks
      expect(await aeraProvisioner.owner()).to.equal(owner.address);
      expect(await aeraPriceAndFeeCalculator.owner()).to.equal(owner.address);
      expect(await aeraProvisioner.authority()).to.not.equal(ZeroAddress);

      // initial vault state
      expect(await aeraMultiDepositorVault.totalSupply()).to.equal(0);
      expect(await testUSDC.balanceOf(await aeraMultiDepositorVault.getAddress())).to.equal(0);

      const tokensIn = parseUnits("10000", 6); // 10,000 USDC
      await testUSDC.connect(alice).approve(await aeraProvisioner.getAddress(), tokensIn);

      // compute a conservative minUnitsOut based on current price
      // 0 = rounding down
      const rawUnits = await aeraPriceAndFeeCalculator.convertTokenToUnitsIfActive(
        await aeraMultiDepositorVault.getAddress(),
        await testUSDC.getAddress(),
        tokensIn,
        0,
      );

      // optional extra safety margin for slippage in tests
      const slippageBps = 300n; // 3% recommended in aera docs
      const minUnitsOut = rawUnits - (rawUnits * slippageBps) / 10000n;

      const now = await shared.getCurrentBlockTimestamp();

      const tx = await aeraProvisioner.connect(alice).requestDeposit(
        await testUSDC.getAddress(), // token
        tokensIn,                    // tokensIn
        minUnitsOut,                 // minUnitsOut
        0,                           // solverTip
        now + 3 * 24 * 60 * 60,      // deadline = now + 3 days
        3600,                        // maxPriceAge
        false,                       // isFixedPrice
      );

      const receipt = await tx.wait();

      // assert the DepositRequested event was emitted and capture the request id
      const logs = receipt.logs;
      const parsedDepositRequestedEvent = logs.map((rawLog: Log) => {
        try {
          return aeraProvisioner.interface.parseLog(rawLog);
        } catch {
          return null;
        }
      }).find((parsedLog: Log) => parsedLog !== null && parsedLog.name === "DepositRequested");

      expect(parsedDepositRequestedEvent, "DepositRequested event not emitted").to.not.equal(null);
      const requestId = parsedDepositRequestedEvent!.args?.requestId ?? parsedDepositRequestedEvent!.args?.id;

      // funds should be held by provisioner, not the vault
      expect(await testUSDC.balanceOf(await aeraProvisioner.getAddress())).to.equal(tokensIn);
      expect(await testUSDC.balanceOf(await aeraMultiDepositorVault.getAddress())).to.equal(0);

      // no units should be minted yet
      expect(await aeraMultiDepositorVault.balanceOf(alice.address)).to.equal(0);
      expect(await aeraMultiDepositorVault.totalSupply()).to.equal(0);

      // basic request bookkeeping sanity if view helpers exist
      // ignore if your mock doesn’t expose them
      if (aeraProvisioner.requests) {
        const r = await aeraProvisioner.requests(requestId);
        expect(r.requester).to.equal(alice.address);
        expect(r.amount).to.equal(tokensIn);
      }
    });

    it("test asset price rises % and conversions", async () => {
      const {
        owner,
        alice,
        testUSDC,
        aeraProvisioner,
        aeraPriceAndFeeCalculator,
        aeraMultiDepositorVault,
      } = await getMockedGauntlet();

      const depositAmountTokens = parseUnits("10000", 6); // 10,000 USDC
      const roundingModeFloor = 0;

      // compute the units implied by the current price
      const unitsBeforePriceIncrease =
        await aeraPriceAndFeeCalculator.convertTokenToUnitsIfActive(
          await aeraMultiDepositorVault.getAddress(),
          await testUSDC.getAddress(),
          depositAmountTokens,
          roundingModeFloor,
        );

      // choose a conservative minUnitsOut (3% slippage buffer)
      const slippageBps = 300n;
      const minUnitsOutForRequest =
        unitsBeforePriceIncrease - (unitsBeforePriceIncrease * slippageBps) / 10_000n;

      // approve and request async deposit
      await testUSDC.connect(alice).approve(await aeraProvisioner.getAddress(), depositAmountTokens);
      const currentTimestamp = await shared.getCurrentBlockTimestamp();

      const tx = await aeraProvisioner.connect(alice).requestDeposit(
        await testUSDC.getAddress(),              // token
        depositAmountTokens,                      // tokensIn
        minUnitsOutForRequest,                    // minUnitsOut
        0,                                        // solverTip
        currentTimestamp + 3 * 24 * 60 * 60,      // deadline in 3 days
        3600,                                     // maxPriceAge
        false,                                    // isFixedPrice
      );

      await expect(tx).to.emit(aeraProvisioner, "DepositRequested");

      // after request, funds are escrowed on provisioner, not in the vault
      expect(await testUSDC.balanceOf(await aeraProvisioner.getAddress()))
        .to.equal(depositAmountTokens);
      expect(await testUSDC.balanceOf(await aeraMultiDepositorVault.getAddress())).to.equal(0);
      expect(await aeraMultiDepositorVault.totalSupply()).to.equal(0);
      expect(await aeraMultiDepositorVault.balanceOf(alice.address)).to.equal(0);

      // simulate +10% unit price
      // price is quoted in USDC 6 decimals
      const newTimestamp = currentTimestamp + 60;
      const pricePlus10Pct = parseUnits("1.10", 6);

      await time.setNextBlockTimestamp(newTimestamp);

      await aeraPriceAndFeeCalculator.connect(owner).setUnitPrice(
        await aeraMultiDepositorVault.getAddress(),
        pricePlus10Pct,
        newTimestamp,
      );

      // conversions should yield fewer units for the same USDC after price increase
      const unitsAfterPriceIncrease =
        await aeraPriceAndFeeCalculator.convertTokenToUnitsIfActive(
          await aeraMultiDepositorVault.getAddress(),
          await testUSDC.getAddress(),
          depositAmountTokens,
          roundingModeFloor,
        );

      // expected ≈ unitsBefore / 1.10 (with floor rounding)
      const expectedUnitsAfterIncrease =
        (unitsBeforePriceIncrease * 10_000n) / 11_000n;

      expect(unitsAfterPriceIncrease).to.equal(expectedUnitsAfterIncrease);
    });
  });

  describe("Gauntlet Strategy", function () {
    it("wires Diamond, stake token, revenue asset, route, and VaultInfo", async function () {
      const {
        hyperStaking, gauntletStrategy, principalToken, vaultShares,
      } = await loadFixture(deployHyperStaking);

      const { diamond, testUSDC, hyperFactory, hyperlaneHandler } = hyperStaking;

      // diamond and stake token
      expect(await gauntletStrategy.DIAMOND()).to.equal(diamond);

      const stakeCurrency = await gauntletStrategy.stakeCurrency();
      expect(stakeCurrency.token).to.equal(testUSDC);

      // revenue asset set
      const revenueAssetAddr = await gauntletStrategy.revenueAsset();
      expect(revenueAssetAddr).to.not.equal(ZeroAddress);

      // hyperlane route exists and vaultShares assigned
      const [exists, ,, vAssetToken, vSharesAddr] =
        await hyperlaneHandler.getRouteInfo(gauntletStrategy);
      expect(exists).to.equal(true);
      expect(vSharesAddr).to.not.equal(ZeroAddress);

      expect(vAssetToken).to.equal(principalToken.target);
      expect(vSharesAddr).to.equal(vaultShares.target);

      // vaultInfo reflects strategy and stake token
      const vInfo = await hyperFactory.vaultInfo(gauntletStrategy);
      expect(vInfo.enabled).to.equal(true);
      expect(vInfo.direct).to.equal(false);
      expect(vInfo.stakeCurrency).to.deep.equal([await testUSDC.getAddress()]);
      expect(vInfo.strategy).to.equal(await gauntletStrategy.getAddress());
      expect(vInfo.revenueAsset).to.equal(revenueAssetAddr);
    });

    it("stake: single user, events, stakeInfo, lockbox & LP balances", async function () {
      const {
        hyperStaking,
        gauntletStrategy,
        vaultShares,
        signers,
      } = await loadFixture(deployHyperStaking);

      const { deposit, allocation, lockbox, testUSDC } = hyperStaking;
      const { alice } = signers;

      const stakeAmount = parseUnits("1000", 6);

      // preview expected allocation in revenue token units
      const expectedAlloc = await gauntletStrategy.previewAllocation(stakeAmount);

      // approve USDC and stake
      await testUSDC.connect(alice).approve(deposit, stakeAmount);

      const reqId = 1;
      const readyAt = 0;

      const tx = await deposit.connect(alice).stakeDeposit(gauntletStrategy, alice, stakeAmount);

      await expect(tx)
        .to.emit(gauntletStrategy, "AllocationRequested")
        .withArgs(reqId, alice, stakeAmount, readyAt);

      await expect(tx)
        .to.emit(gauntletStrategy, "AllocationClaimed")
        .withArgs(reqId, lockbox.target, expectedAlloc);

      // stakeInfo updated
      const stakeInfo = await allocation.stakeInfo(gauntletStrategy);
      expect(stakeInfo.totalStake).to.equal(stakeAmount);
      expect(stakeInfo.totalAllocation).to.equal(expectedAlloc);

      // lockbox holds revenue asset (receipt/units)
      const revenueAssetAddr = await gauntletStrategy.revenueAsset();
      const revenueAsset = await ethers.getContractAt("LumiaGtUSDaAllocation", revenueAssetAddr);
      expect(await revenueAsset.balanceOf(lockbox)).to.equal(expectedAlloc);

      // LP (vault shares on Lumia chain) minted to user
      expect(await vaultShares.balanceOf(alice)).to.equal(stakeAmount);
    });

    it("stake: two users, interleaved; sums, LP balances correct", async function () {
      const {
        hyperStaking,
        gauntletStrategy,
        vaultShares,
        signers,
      } = await loadFixture(deployHyperStaking);

      const { deposit, allocation, lockbox, testUSDC } = hyperStaking;
      const { alice, bob } = signers;

      const aliceStake = parseUnits("1200", 6);
      const bobStake = parseUnits("350", 6);

      const aliceAlloc = await gauntletStrategy.previewAllocation(aliceStake);
      const bobAlloc = await gauntletStrategy.previewAllocation(bobStake);

      await testUSDC.connect(alice).approve(deposit, aliceStake);
      await testUSDC.connect(bob).approve(deposit, bobStake);

      // alice first
      const aliceReqId = 1;
      await expect(
        deposit.connect(alice).stakeDeposit(gauntletStrategy, alice, aliceStake),
      )
        .to.emit(gauntletStrategy, "AllocationRequested")
        .withArgs(aliceReqId, alice, aliceStake, 0)
        .and.to.emit(gauntletStrategy, "AllocationClaimed")
        .withArgs(aliceReqId, lockbox.target, aliceAlloc);

      // bob next
      const bobReqId = 2;
      await expect(
        deposit.connect(bob).stakeDeposit(gauntletStrategy, bob, bobStake),
      )
        .to.emit(gauntletStrategy, "AllocationRequested")
        .withArgs(bobReqId, bob, bobStake, 0)
        .and.to.emit(gauntletStrategy, "AllocationClaimed")
        .withArgs(bobReqId, lockbox.target, bobAlloc);

      // stakeInfo totals
      const stakeInfo = await allocation.stakeInfo(gauntletStrategy);
      expect(stakeInfo.totalStake).to.equal(aliceStake + bobStake);
      expect(stakeInfo.totalAllocation).to.equal(aliceAlloc + bobAlloc);

      // lockbox holds combined allocation units (revenue asset)
      const revenueAsset = await ethers.getContractAt(
        "LumiaGtUSDaAllocation",
        await gauntletStrategy.revenueAsset(),
      );
      expect(await revenueAsset.balanceOf(lockbox)).to.equal(aliceAlloc + bobAlloc);

      // LP balances reflect staked USDC on Lumia side
      expect(await vaultShares.balanceOf(alice)).to.equal(aliceStake);
      expect(await vaultShares.balanceOf(bob)).to.equal(bobStake);
    });

    it("stake & redeem with 3% slippage", async function () {
      const {
        hyperStaking,
        gauntletStrategy,
        vaultShares,
        signers,
        aeraMock,
      } = await loadFixture(deployHyperStaking);

      const { deposit, allocation, realAssets, testUSDC } = hyperStaking;
      const { alice, stakingManager, strategyManager } = signers;

      // --- configure slippage back to 3% ---
      const cfg = await gauntletStrategy.aeraConfig();
      await gauntletStrategy.connect(strategyManager).setAeraConfig({
        solverTip: cfg.solverTip,
        deadlineOffset: cfg.deadlineOffset,
        maxPriceAge: cfg.maxPriceAge,
        slippageBps: 300,
        isFixedPrice: cfg.isFixedPrice,
      } as AeraConfigStruct);

      // increase allowed withdraw loss to 6% (to allow for 3% in and 3% out)
      await deposit.connect(stakingManager).setAllowedWithdrawLoss(parseEther("0.06"));

      const stakeAmount = parseUnits("1000", 6);
      await testUSDC.connect(alice).approve(deposit, stakeAmount);

      // preview allocation (should include 3% slippage)
      const expectedAlloc = await gauntletStrategy.previewAllocation(stakeAmount);

      // also compute raw units via calculator to verify ~3% reduction
      const ROUND_FLOOR = 0;
      const rawUnits = await aeraMock.aeraPriceAndFeeCalculator.convertTokenToUnitsIfActive(
        await aeraMock.aeraMultiDepositorVault.getAddress(),
        await testUSDC.getAddress(),
        stakeAmount,
        ROUND_FLOOR,
      );
      // expect alloc to be strictly less than raw units (≈ -3%, allow off-by rounding)
      const precisionError = 1n;
      expect(expectedAlloc - precisionError).to.be.eq(rawUnits - (rawUnits * 300n) / 10_000n);

      // --- Stake & settle deposit ---
      const stakeTx = await deposit.connect(alice).stakeDeposit(gauntletStrategy, alice, stakeAmount);
      await shared.solveGauntletDepositRequest(
        stakeTx, gauntletStrategy, aeraMock.aeraProvisioner, testUSDC, stakeAmount, 1,
      );

      // LP 1:1 in stake units
      const userShares = await vaultShares.balanceOf(alice);
      expect(userShares).to.equal(stakeAmount);

      // --- 1/2 redeem ---
      const redeemShares = userShares / 2n;
      await vaultShares.connect(alice).approve(realAssets, redeemShares);

      // amount of *shares* the strategy will need to exit (units side)
      const redeemTx = await realAssets.connect(alice)
        .redeem(gauntletStrategy, alice, alice, redeemShares);

      const aeraConfig = await gauntletStrategy.aeraConfig();
      const deadline = BigInt(await shared.getCurrentBlockTimestamp()) + aeraConfig.deadlineOffset;

      // recordedExit is the min tokens-out (USDC), includes 3% slippage on exit
      const requestId = 2;
      const minTokensOut = await gauntletStrategy.recordedExit(requestId);
      expect(minTokensOut).to.be.gt(0);

      // for visibility: tokens-out should be < stakeAmount due to slippage
      expect(minTokensOut).to.be.lt(stakeAmount);

      // --- Settle redeem & claim ---
      await shared.solveGauntletRedeemRequest(
        redeemTx, gauntletStrategy, aeraMock.aeraProvisioner, testUSDC, minTokensOut, requestId,
      );

      await time.setNextBlockTimestamp(Number(deadline));
      const lastId = await shared.getLastClaimId(deposit, gauntletStrategy, alice);
      const claimTx = await deposit.connect(alice).claimWithdraws([lastId], alice);

      // ExitClaimed with the conservative minTokensOut
      await expect(claimTx)
        .to.emit(gauntletStrategy, "ExitClaimed")
        .withArgs(requestId, alice, minTokensOut);

      // funds flow: strategy USDC -> alice
      await expect(claimTx)
        .to.changeTokenBalances(
          testUSDC,
          [gauntletStrategy, alice],
          [-minTokensOut, minTokensOut],
        );

      // position fully closed (no price change, so allocation should zero out)
      const stakeInfo = await allocation.stakeInfo(gauntletStrategy);
      expect(stakeInfo.totalStake).to.equal(stakeAmount / 2n);
      expect(stakeInfo.totalAllocation).to.equal(expectedAlloc / 2n - precisionError);
      expect(await vaultShares.balanceOf(alice)).to.equal(userShares - redeemShares);
    });

    it("redeem after +10% price increase, claim, and balances", async function () {
      const {
        hyperStaking,
        gauntletStrategy,
        vaultShares,
        signers,
        aeraMock,
      } = await loadFixture(deployHyperStaking);

      const {
        deposit,
        allocation,
        realAssets,
        lockbox,
        testUSDC,
      } = hyperStaking;
      const { alice, owner } = signers;

      // ---------- Stake ----------
      const stakeAmount = parseUnits("1000", 6);
      await testUSDC.connect(alice).approve(deposit, stakeAmount);

      const expectedAllocation = await gauntletStrategy.previewAllocation(stakeAmount);

      const stakeTx = await deposit.connect(alice).stakeDeposit(gauntletStrategy, alice, stakeAmount);

      await expect(stakeTx)
        .to.emit(gauntletStrategy, "AllocationRequested").withArgs(1, alice, stakeAmount, 0)
        .and.to.emit(gauntletStrategy, "AllocationClaimed").withArgs(1, lockbox.target, expectedAllocation);

      const reqId = 1;
      await shared.solveGauntletDepositRequest(
        stakeTx, gauntletStrategy, aeraMock.aeraProvisioner, testUSDC, stakeAmount, reqId,
      );

      // sanity: LP shares minted 1:1 in Lumia
      expect(await vaultShares.balanceOf(alice)).to.equal(stakeAmount);

      // ---------- Raise unit price by +10% ----------

      const currentTs = await shared.getCurrentBlockTimestamp();
      const newTs = currentTs + 60;
      const pricePlus10Pct = parseUnits("1.10", 6);

      await time.setNextBlockTimestamp(newTs);
      await aeraMock.aeraPriceAndFeeCalculator
        .connect(owner)
        .setUnitPrice(
          await aeraMock.aeraMultiDepositorVault.getAddress(),
          pricePlus10Pct,
          newTs,
        );

      // ---------- Queue full redeem ----------

      const lumiaShares = await vaultShares.balanceOf(alice);
      await vaultShares.connect(alice).approve(realAssets, lumiaShares);

      const redeemTx = await realAssets
        .connect(alice)
        .redeem(gauntletStrategy, alice, alice, lumiaShares);

      const deadline = BigInt(newTs) + (await gauntletStrategy.aeraConfig()).deadlineOffset;

      const expectedExitShares = await gauntletStrategy.previewAllocation(stakeAmount);
      const expectedExitAmount = await gauntletStrategy.previewExit(expectedExitShares);

      await expect(redeemTx)
        .to.emit(gauntletStrategy, "ExitRequested")
        .withArgs(2, alice, expectedExitShares, deadline);

      // recordedExit must be set
      expect(await gauntletStrategy.recordedExit(2)).to.equal(expectedExitAmount);

      await shared.solveGauntletRedeemRequest(
        redeemTx, gauntletStrategy, aeraMock.aeraProvisioner, testUSDC, expectedExitAmount, 2,
      );

      // ---------- Claim after delay ----------

      await time.setNextBlockTimestamp(deadline);

      const lastClaimId = await shared.getLastClaimId(deposit, gauntletStrategy, alice);
      const claimTx = await deposit.connect(alice).claimWithdraws([lastClaimId], alice);

      await expect(claimTx)
        .to.emit(gauntletStrategy, "ExitClaimed")
        .withArgs(2, alice, expectedExitAmount);

      // funds flow: gauntletStrategy USDC -> alice
      await expect(claimTx)
        .to.changeTokenBalances(
          testUSDC,
          [gauntletStrategy, alice],
          [-expectedExitAmount, expectedExitAmount],
        );

      // ---------- Post-state: zeroed position ----------

      const stakeInfo = await allocation.stakeInfo(gauntletStrategy);
      expect(stakeInfo.totalStake).to.equal(0);
      expect(await vaultShares.balanceOf(alice)).to.equal(0);

      // because of +10% price, allocation needed is lower than initial
      expect(stakeInfo.totalAllocation).to.gt(0);
    });

    it("requires feeRecipient; then compounds revenue with feeRate=0", async function () {
      const {
        hyperStaking,
        gauntletStrategy,
        principalToken,
        vaultShares,
        signers,
        aeraMock,
      } = await loadFixture(deployHyperStaking);

      const {
        deposit, allocation, realAssets, testUSDC, hyperFactory,
      } = hyperStaking;
      const { alice, owner, vaultManager, bob } = signers;

      // ---------- Stake ----------
      const stakeAmount = parseUnits("1500", 6);
      await testUSDC.connect(alice).approve(deposit, stakeAmount);

      const stakeTx = await deposit.connect(alice).stakeDeposit(gauntletStrategy, alice, stakeAmount);

      await shared.solveGauntletDepositRequest(
        stakeTx, gauntletStrategy, aeraMock.aeraProvisioner, testUSDC, stakeAmount, 1n,
      );

      expect(await vaultShares.balanceOf(alice)).to.eq(stakeAmount);

      // ---------- Price +10% (units more valuable) ----------

      const now = await shared.getCurrentBlockTimestamp();
      await time.setNextBlockTimestamp(now + 60);
      await aeraMock.aeraPriceAndFeeCalculator
        .connect(owner)
        .setUnitPrice(
          await aeraMock.aeraMultiDepositorVault.getAddress(),
          parseUnits("1.10", 6),
          now + 60,
        );

      // ---------- Full redeem for user ----------

      const lumiaShares = await vaultShares.balanceOf(alice);
      await vaultShares.connect(alice).approve(realAssets, lumiaShares);

      const redeemTx = await realAssets.connect(alice)
        .redeem(gauntletStrategy, alice, alice, lumiaShares);

      const aeraConfig = await gauntletStrategy.aeraConfig();
      const deadline = BigInt(now + 60) + aeraConfig.deadlineOffset;

      // check ExitRequested event
      const expectedExitShares = await gauntletStrategy.previewAllocation(stakeAmount);
      await expect(redeemTx)
        .to.emit(gauntletStrategy, "ExitRequested")
        .withArgs(2, alice, expectedExitShares, deadline);

      const expectedExitAmount = await gauntletStrategy.previewExit(expectedExitShares);
      expect(await gauntletStrategy.recordedExit(2)).to.equal(expectedExitAmount);

      await shared.solveGauntletRedeemRequest(
        redeemTx, gauntletStrategy, aeraMock.aeraProvisioner, testUSDC, expectedExitAmount, 2,
      );

      await time.setNextBlockTimestamp(Number(deadline));
      const lastId = await shared.getLastClaimId(deposit, gauntletStrategy, alice);
      await expect(deposit.connect(alice).claimWithdraws([lastId], alice))
        .to.emit(gauntletStrategy, "ExitClaimed")
        .withArgs(2, alice, expectedExitAmount);

      // user fully out; totalStake==0, but totalAllocation > 0 (revenue left in units)
      let si = await allocation.stakeInfo(gauntletStrategy);
      expect(si.totalStake).to.eq(0);
      expect(si.totalAllocation).to.gt(0);

      // ---------- Report flow ----------
      const expectedRevenue = await allocation.checkRevenue(gauntletStrategy);
      expect(expectedRevenue).to.be.gt(0);

      // must set feeRecipient first
      await expect(allocation.connect(vaultManager).report(gauntletStrategy))
        .to.be.revertedWithCustomError(allocation, "FeeRecipientUnset");

      await allocation.connect(vaultManager).setFeeRecipient(gauntletStrategy, bob);

      // ensure feeRate = 0 for this test
      expect((await hyperFactory.vaultInfo(gauntletStrategy)).feeRate).to.eq(0);

      const reportTx = allocation.connect(vaultManager).report(gauntletStrategy);

      await expect(reportTx).to.emit(allocation, "StakeCompounded").withArgs(
        gauntletStrategy, bob, 0, 0, 0, expectedRevenue,
      );

      // totalStake increases by revenue; allocation remains (future reports will eat into it)
      si = await allocation.stakeInfo(gauntletStrategy);
      expect(si.totalStake).to.eq(expectedRevenue);
      expect(await allocation.checkRevenue(gauntletStrategy)).to.be.lte(expectedRevenue); // should not grow

      await expect(reportTx).to.changeTokenBalance(principalToken, vaultShares, expectedRevenue);
    });

    it("compounds before user redeem, user claims more tokens than initial stake", async function () {
      const {
        hyperStaking,
        gauntletStrategy,
        vaultShares,
        signers,
        aeraMock,
      } = await loadFixture(deployHyperStaking);

      const { deposit, allocation, realAssets, testUSDC, hyperFactory } = hyperStaking;
      const { alice, owner, vaultManager, bob } = signers;

      // --- Stake & settle deposit ---
      const stakeAmount = parseUnits("3000", 6);
      await testUSDC.connect(alice).approve(deposit, stakeAmount);

      const stakeTx = await deposit.connect(alice).stakeDeposit(gauntletStrategy, alice, stakeAmount);

      await shared.solveGauntletDepositRequest(
        stakeTx, gauntletStrategy, aeraMock.aeraProvisioner, testUSDC, stakeAmount, 1,
      );

      // --- Price +20% (units more valuable) ---
      const now = await shared.getCurrentBlockTimestamp();
      await time.setNextBlockTimestamp(now + 60);
      await aeraMock.aeraPriceAndFeeCalculator
        .connect(owner)
        .setUnitPrice(
          await aeraMock.aeraMultiDepositorVault.getAddress(),
          parseUnits("1.20", 6),
          now + 60,
        );
      // transfer extra USDC to aera vault
      await testUSDC.mint(aeraMock.aeraMultiDepositorVault, parseUnits("600", 6));

      // --- Report while user is still in ---

      await expect(allocation.connect(vaultManager).report(gauntletStrategy))
        .to.be.revertedWithCustomError(allocation, "FeeRecipientUnset");
      await allocation.connect(vaultManager).setFeeRecipient(gauntletStrategy, bob);

      // ensure 0% fee for this test
      expect((await hyperFactory.vaultInfo(gauntletStrategy)).feeRate).to.eq(0);

      const revenueBefore = await allocation.checkRevenue(gauntletStrategy);
      expect(revenueBefore).to.be.gt(0);

      const reportTx = await allocation.connect(vaultManager).report(gauntletStrategy);
      await expect(reportTx).to.emit(allocation, "StakeCompounded")
        .withArgs(gauntletStrategy, bob, 0, 0, 0, revenueBefore);

      const siAfterReport = await allocation.stakeInfo(gauntletStrategy);
      expect(siAfterReport.totalStake).to.eq(stakeAmount + revenueBefore);

      // --- User queues full redeem & claim ---
      const userShares = await vaultShares.balanceOf(alice);
      await vaultShares.connect(alice).approve(realAssets, userShares);

      // calculate expected exit
      const exitAmount = await vaultShares.previewRedeem(userShares);
      expect(exitAmount).to.be.closeTo(
        userShares + revenueBefore,
        parseUnits("0.0001", 6), // delta tolerance
      );
      const expectedExitShares = await gauntletStrategy.previewAllocation(exitAmount);

      const cfg = await gauntletStrategy.aeraConfig();
      const deadline = BigInt(now + 60) + cfg.deadlineOffset;

      const redeemTx = await realAssets.connect(alice)
        .redeem(gauntletStrategy, alice, alice, userShares);

      await expect(redeemTx)
        .to.emit(gauntletStrategy, "ExitRequested")
        .withArgs(2, alice, expectedExitShares, deadline);

      const minTokensOut = await gauntletStrategy.recordedExit(2);
      expect(minTokensOut).to.be.gt(0);

      // settle redeem and then claim
      await shared.solveGauntletRedeemRequest(
        redeemTx, gauntletStrategy, aeraMock.aeraProvisioner, testUSDC, minTokensOut, 2,
      );

      await time.setNextBlockTimestamp(Number(deadline));
      const lastId = await shared.getLastClaimId(deposit, gauntletStrategy, alice);

      const claimTx = await deposit.connect(alice).claimWithdraws([lastId], alice);
      await expect(claimTx)
        .to.emit(gauntletStrategy, "ExitClaimed")
        .withArgs(2, alice, minTokensOut);

      // user should get more than initial stake
      expect(minTokensOut).to.be.gt(stakeAmount);

      // funds flow: strategy -> user
      await expect(claimTx)
        .to.changeTokenBalances(testUSDC, [gauntletStrategy, alice], [-minTokensOut, minTokensOut]);

      // user position closed
      expect(await vaultShares.balanceOf(alice)).to.eq(0);
    });

    it("errors: guards and config validation", async function () {
      const {
        hyperStaking,
        gauntletStrategy,
        signers,
      } = await loadFixture(deployHyperStaking);

      const { owner, alice, strategyManager } = signers;
      const { diamond } = hyperStaking;

      // -------- onlyLumiaDiamond guard (direct calls revert) --------
      await expect(
        gauntletStrategy.connect(alice).requestAllocation(1, 1, alice),
      ).to.be.revertedWithCustomError(gauntletStrategy, "NotLumiaDiamond");

      await expect(
        gauntletStrategy.connect(alice).claimAllocation([1], alice),
      ).to.be.revertedWithCustomError(gauntletStrategy, "NotLumiaDiamond");

      await expect(
        gauntletStrategy.connect(alice).requestExit(2, 1, alice),
      ).to.be.revertedWithCustomError(gauntletStrategy, "NotLumiaDiamond");

      await expect(
        gauntletStrategy.connect(alice).claimExit([2], alice),
      ).to.be.revertedWithCustomError(gauntletStrategy, "NotLumiaDiamond");

      // -------- impersonate diamond to hit inner validation --------
      await ethers.provider.send("hardhat_impersonateAccount", [await diamond.getAddress()]);
      const diamondAs = await ethers.getSigner(await diamond.getAddress());

      // send ether to diamond to pay for gas
      const tx = await owner.sendTransaction({
        to: await diamond.getAddress(),
        value: parseUnits("1", 18),
      });
      await tx.wait();

      // ZeroUser / ZeroAmount on requestAllocation
      await expect(
        gauntletStrategy.connect(diamondAs).requestAllocation(3, 0, alice),
      ).to.be.revertedWithCustomError(gauntletStrategy, "ZeroAmount");

      await expect(
        gauntletStrategy.connect(diamondAs).requestAllocation(4, 1, ZeroAddress),
      ).to.be.revertedWithCustomError(gauntletStrategy, "ZeroUser");

      // ZeroUser / ZeroAmount on requestExit
      await expect(
        gauntletStrategy.connect(diamondAs).requestExit(5, 0, alice),
      ).to.be.revertedWithCustomError(gauntletStrategy, "ZeroAmount");

      await expect(
        gauntletStrategy.connect(diamondAs).requestExit(6, 1, ZeroAddress),
      ).to.be.revertedWithCustomError(gauntletStrategy, "ZeroUser");

      // ZeroReceiver on claim paths
      await expect(
        gauntletStrategy.connect(diamondAs).claimAllocation([7], ZeroAddress),
      ).to.be.revertedWithCustomError(gauntletStrategy, "ZeroReceiver");

      await expect(
        gauntletStrategy.connect(diamondAs).claimExit([8], ZeroAddress),
      ).to.be.revertedWithCustomError(gauntletStrategy, "ZeroReceiver");

      // -------- strategy manager–only config & bounds --------

      const cfg = (await gauntletStrategy.aeraConfig()) as AeraConfigStruct;

      await expect(
        gauntletStrategy.connect(alice).setAeraConfig({
          solverTip: cfg.solverTip,
          deadlineOffset: cfg.deadlineOffset,
          maxPriceAge: cfg.maxPriceAge,
          slippageBps: cfg.slippageBps,
          isFixedPrice: cfg.isFixedPrice,
        } as AeraConfigStruct),
      ).to.be.revertedWithCustomError(gauntletStrategy, "NotStrategyManager");

      await expect(
        gauntletStrategy.connect(strategyManager).setAeraConfig({
          solverTip: cfg.solverTip,
          deadlineOffset: cfg.deadlineOffset,
          maxPriceAge: cfg.maxPriceAge,
          slippageBps: 10001,
          isFixedPrice: cfg.isFixedPrice,
        } as AeraConfigStruct),
      ).to.be.revertedWithCustomError(gauntletStrategy, "InvalidConfig");

      // happy path (within 0..10000)
      await gauntletStrategy.connect(strategyManager).setAeraConfig({
        solverTip: cfg.solverTip,
        deadlineOffset: cfg.deadlineOffset,
        maxPriceAge: cfg.maxPriceAge,
        slippageBps: 543,
        isFixedPrice: cfg.isFixedPrice,
      } as AeraConfigStruct);
      const newCfg = await gauntletStrategy.aeraConfig();
      expect(newCfg.slippageBps).to.equal(543);
    });
  });
});
