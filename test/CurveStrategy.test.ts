import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

import { ethers, ignition } from "hardhat";
import { parseEther, parseUnits, Contract, ZeroAddress } from "ethers";
import SwapSuperStrategyModule from "../ignition/modules/SwapSuperStrategy";
import TestSwapIntegrationModule from "../ignition/modules/test/TestSwapIntegration.ts";

import { ISuperformIntegration } from "../typechain-types";

import { expect } from "chai";
import * as shared from "./shared";

const stableUnits = (val: string) => parseUnits(val, 6);

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n);

  // -------------------- Apply Strategies --------------------

  const testUSDCAddr = await hyperStaking.testUSDC.getAddress();
  const testUSDTAddr = await hyperStaking.testUSDT.getAddress();

  const { swapSuperStrategy } = await ignition.deploy(SwapSuperStrategyModule, {
    parameters: {
      SwapSuperStrategyModule: {
        diamond: await hyperStaking.diamond.getAddress(),
        curveInputToken: testUSDTAddr,
        curvePool: await hyperStaking.curvePool.getAddress(),
        superVault: await hyperStaking.superVault.getAddress(),
        superformInputToken: testUSDCAddr,
      },
    },
  });

  // ------------------ SuperUSDC ------------------

  const superUSDC = await shared.registerAERC20( // transmuted ERC20 version
    hyperStaking.superformIntegration, hyperStaking.superVault, hyperStaking.testUSDC,
  );

  // ------------------ CurveIntegration ------------------

  const nCoins = 3n; // simulating 3pool
  const testDAIAddr = ZeroAddress; // not used in mock
  const registerTokens = [testDAIAddr, testUSDCAddr, testUSDTAddr];
  const indexes = [0n, 1n, 2n];
  await hyperStaking.curveIntegration.connect(signers.strategyManager).registerPool(
    hyperStaking.curvePool,
    nCoins,
    registerTokens,
    indexes,
  );

  // --------------------

  const vaultTokenName = "Lumia USDT SwapSuper Position";
  const vaultTokenSymbol = "lspUSDT";

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    swapSuperStrategy,
    vaultTokenName,
    vaultTokenSymbol,
  );

  await hyperStaking.superformIntegration.connect(signers.strategyManager).updateSuperformStrategies(
    swapSuperStrategy,
    true,
  );

  await hyperStaking.curveIntegration.connect(signers.strategyManager).updateSwapStrategies(
    swapSuperStrategy,
    true,
  );

  // -------------------- Hyperlane Handler --------------------

  const { principalToken, vaultShares } = await shared.getDerivedTokens(
    hyperStaking.hyperlaneHandler,
    await swapSuperStrategy.getAddress(),
  );

  // --------------------

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    swapSuperStrategy, superUSDC, principalToken, vaultShares, // test contracts
    vaultTokenName, vaultTokenSymbol, // values
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

describe("CurveStrategy", function () {
  // ------------------ Helper ------------------
  function oneHopRoute(
    pool: string,
    tokenIn: string,
    tokenOut: string,
    indexes: [bigint, bigint] = [1n, 2n], // default USDC (1) -> USDT (2)
  ): [
    string[],
    [
      [bigint, bigint, bigint, bigint, bigint],
      [bigint, bigint, bigint, bigint, bigint],
      [bigint, bigint, bigint, bigint, bigint],
      [bigint, bigint, bigint, bigint, bigint],
      [bigint, bigint, bigint, bigint, bigint],
    ],
    [string, string, string, string, string],
  ] {
    // route[11]
    const route = Array(11).fill(ZeroAddress);
    route[0] = tokenIn;
    route[1] = pool;
    route[2] = tokenOut;

    // works only with 2 tokens, there is no check for length
    const i = indexes[0];
    const j = indexes[1];

    // swap_params[5][5] – only first row matters; explicit tuple typing
    const params:
    [
      [bigint, bigint, bigint, bigint, bigint],
      [bigint, bigint, bigint, bigint, bigint],
      [bigint, bigint, bigint, bigint, bigint],
      [bigint, bigint, bigint, bigint, bigint],
      [bigint, bigint, bigint, bigint, bigint],
    ] = [
      [i, j, 1n, 1n, 3n],
      [0n, 0n, 0n, 0n, 0n],
      [0n, 0n, 0n, 0n, 0n],
      [0n, 0n, 0n, 0n, 0n],
      [0n, 0n, 0n, 0n, 0n],
    ]; // indexes ignored by mock

    // pools[5]
    const pools: [string, string, string, string, string] = [
      ZeroAddress,
      ZeroAddress,
      ZeroAddress,
      ZeroAddress,
      ZeroAddress,
    ];

    return [route, params, pools];
  }

  async function createMockedCurvePool(
    token1: Contract,
    token2: Contract,
    fillAmount: bigint = parseEther("100"),
  ) {
    const curvePool = await ethers.deployContract("MockCurvePool", [
      await token1.getAddress(),
      await token2.getAddress(),
    ]);

    // fill the pool with tokens
    await token1.transfer(await curvePool.getAddress(), fillAmount);
    await token2.transfer(await curvePool.getAddress(), fillAmount);

    return curvePool;
  }

  async function getMockedCurve() {
    const signers = await shared.getSigners();
    const { owner } = signers;

    // -------------------- Deploy Tokens --------------------

    const usdc = await shared.deloyTestERC20("Test USDC", "tUSDC", 6);
    const usdt = await shared.deloyTestERC20("Test USDT", "tUSDT", 6);

    await usdc.mint(owner, stableUnits("1000000"));
    await usdt.mint(owner, stableUnits("1000000"));

    // ------------------ Mock Curve Router ------------------

    const curvePool = await createMockedCurvePool(usdc, usdt, stableUnits("500000"));
    const curveRouter = await ethers.deployContract("MockCurveRouter");

    return { curvePool, curveRouter, usdc, usdt, owner };
  }

  describe("Curve Mock Router", function () {
    it("real get_dy / get_dx reflect the rate", async function () {
      const { curvePool, curveRouter, usdc, usdt } = await loadFixture(getMockedCurve);

      const amount = parseUnits("100", 6);
      const [route, params, pools] = oneHopRoute(
        await curvePool.getAddress(),
        await usdc.getAddress(),
        await usdt.getAddress(),
      );

      // 1:1 rate (default)
      let dy = await curveRouter.get_dy(route, params, amount, pools);
      expect(dy).to.equal(amount);

      // change rate to 0.98
      await curvePool.setRate(parseUnits("0.98", 18));
      dy = await curveRouter.get_dy(route, params, amount, pools);
      expect(dy).to.equal((amount)); // still 1:1

      // but real
      expect(await curvePool.realDy(amount)).to.equal((amount * 98n) / 100n);

      // dx should invert dy
      const dx = await curveRouter.get_dx(
        route,
        params,
        dy,
        pools,
        [ZeroAddress, ZeroAddress, ZeroAddress, ZeroAddress, ZeroAddress],
        [ZeroAddress, ZeroAddress, ZeroAddress, ZeroAddress, ZeroAddress],
      );
      expect(dx).to.equal(amount);
    });

    it("exchange USDC -> USDT transfers and returns dy", async function () {
      const { curvePool, curveRouter, usdc, usdt, owner } = await loadFixture(getMockedCurve);

      const amountIn = parseUnits("1000", 6);
      const [route, params, pools] = oneHopRoute(
        await curvePool.getAddress(),
        await usdc.getAddress(),
        await usdt.getAddress(),
      );

      await usdc.approve(await curveRouter.getAddress(), amountIn);

      const balBefore = await usdt.balanceOf(owner);

      // Dry run to get expected output
      const dy = await curveRouter.exchange.staticCall(
        route,
        params,
        amountIn,
        0,
        pools,
        owner,
      );

      // Real transaction
      await curveRouter.exchange(route, params, amountIn, 0, pools, owner.address);
      const balAfter = await usdt.balanceOf(owner.address);

      expect(balAfter - balBefore).to.equal(dy);
      expect(dy).to.equal(amountIn);
    });

    it("exchange USDT -> USDC transfers and returns dy", async function () {
      const { curvePool, curveRouter, usdc, usdt, owner } = await loadFixture(getMockedCurve);

      const amountIn = parseUnits("500", 6);

      const [route, params, pools] = oneHopRoute(
        await curvePool.getAddress(),
        await usdt.getAddress(),
        await usdc.getAddress(),
        [2n, 1n], // USDT (2) -> USDC (1)
      );

      await usdt.approve(await curveRouter.getAddress(), amountIn);

      const balBefore = await usdc.balanceOf(owner.address);
      const dy = await curveRouter.exchange.staticCall(
        route,
        params,
        amountIn,
        0n,
        pools,
        owner,
      );

      await curveRouter.exchange(route, params, amountIn, 0n, pools, owner);
      const balAfter = await usdc.balanceOf(owner.address);

      expect(balAfter - balBefore).to.equal(dy);
    });
  });

  describe("Swap Test Integration", function () {
    async function getMockedIntegrations() {
      const signers = await shared.getSigners();
      const { curvePool, curveRouter, usdc, usdt } = await loadFixture(getMockedCurve);

      await usdc.mint(signers.alice.address, parseUnits("10000", 6));
      await usdt.mint(signers.alice.address, parseUnits("10000", 6));

      const erc4626Vault = await shared.deloyTestERC4626Vault(usdc);

      const {
        superformFactory, superformRouter, superVault, superPositions,
      } = await shared.deploySuperformMock(erc4626Vault);

      const { testSwapIntegration } = await ignition.deploy(TestSwapIntegrationModule, {
        parameters: {
          TestSwapIntegrationModule: {
            superformFactory: await superformFactory.getAddress(),
            superformRouter: await superformRouter.getAddress(),
            superPositions: await superPositions.getAddress(),
            curveRouter: await curveRouter.getAddress(),
          },
        },
      });

      // create strategy
      const { swapSuperStrategy } = await ignition.deploy(SwapSuperStrategyModule, {
        parameters: {
          SwapSuperStrategyModule: {
            diamond: await testSwapIntegration.getAddress(), // using testSwapIntegration as a diamond
            curveInputToken: await usdt.getAddress(),
            curvePool: await curvePool.getAddress(),
            superVault: await superVault.getAddress(),
            superformInputToken: await usdc.getAddress(),
          },
        },
      });

      // ------------------ Add Strategy ------------------

      await testSwapIntegration.connect(signers.owner).updateSuperformStrategies(
        swapSuperStrategy,
        true,
      );

      await testSwapIntegration.connect(signers.owner).updateSwapStrategies(
        swapSuperStrategy,
        true,
      );

      // ------------------ SuperUSDC ------------------

      const superUSDC = await shared.registerAERC20( // transmuted ERC20 version
        testSwapIntegration as unknown as ISuperformIntegration, superVault, usdc,
      );

      // ------------------ CurveIntegration ------------------

      const nCoins = 3n; // simulating 3pool
      const testDAIAddr = ZeroAddress; // not used in mock
      const registerTokens = [testDAIAddr, usdc.target, usdt.target];
      const indexes = [0n, 1n, 2n];
      await testSwapIntegration.connect(signers.owner).registerPool(
        curvePool,
        nCoins,
        registerTokens,
        indexes,
      );

      /* eslint-disable object-property-newline */
      return {
        testSwapIntegration, // integration
        swapSuperStrategy, // strategy
        usdt, usdc, erc4626Vault, superUSDC, // tokens
        curvePool, curveRouter, superformFactory, superformRouter, superVault, superPositions, // mocks
        signers, // signers
      };
      /* eslint-disable object-property-newline */
    }

    it("check for bad route and tokens", async function () {
      const { testSwapIntegration, usdc, usdt, superVault, signers } = await loadFixture(getMockedIntegrations);

      // -------------------- setup

      const badToken = await shared.deloyTestERC20("Test BAD1", "BB1", 6);

      const { owner, alice } = signers;
      await badToken.mint(owner, stableUnits("1000000"));
      await badToken.mint(alice, stableUnits("1000000"));

      const strangePool = await createMockedCurvePool(badToken, usdc, stableUnits("500000"));

      // create strategy which uses not registered tokens
      const strangeStrategy = (await ignition.deploy(SwapSuperStrategyModule, {
        parameters: {
          SwapSuperStrategyModule: {
            diamond: await testSwapIntegration.getAddress(), // using testSwapIntegration as a diamond
            curveInputToken: await badToken.getAddress(),
            curvePool: await strangePool.getAddress(),
            superVault: await superVault.getAddress(),
            superformInputToken: await usdc.getAddress(),
          },
        },
      })).swapSuperStrategy;

      // -------------------- actual test

      const amount = parseUnits("321", 6);

      await badToken.connect(alice).approve(testSwapIntegration, amount);

      await expect(testSwapIntegration.connect(alice).allocate(strangeStrategy, amount))
        .to.be.revertedWithCustomError(testSwapIntegration, "PoolNotRegistered");

      // register pool with wrong tokens
      let nCoins = 2n;
      let registerTokens = [usdc.target, usdt.target]; // missing badToken
      let indexes = [0n, 1n];
      await testSwapIntegration.registerPool(
        strangePool,
        nCoins,
        registerTokens,
        indexes,
      );

      await expect(testSwapIntegration.connect(alice).allocate(strangeStrategy, amount))
        .to.be.revertedWithCustomError(testSwapIntegration, "TokenNotRegistered")
        .withArgs(badToken);

      // register bad again
      nCoins = 2n;
      registerTokens = [badToken.target, usdt.target]; // usdt instead of usdc
      indexes = [45n, 4n]; // strange indexes
      await testSwapIntegration.registerPool(
        strangePool,
        nCoins,
        registerTokens,
        indexes,
      );

      await expect(testSwapIntegration.connect(alice).allocate(strangeStrategy, amount))
        .to.be.revertedWithCustomError(testSwapIntegration, "TokenNotRegistered")
        .withArgs(usdc);

      // register correctly
      nCoins = 2n;
      registerTokens = [badToken.target, usdc.target]; // usdt instead of usdc
      indexes = [0n, 1n]; // strange indexes
      await testSwapIntegration.registerPool(
        strangePool,
        nCoins,
        registerTokens,
        indexes,
      );

      await expect(testSwapIntegration.connect(alice).allocate(strangeStrategy, amount))
        .to.be.revertedWithCustomError(testSwapIntegration, "NotFromSwapStrategy")
        .withArgs(strangeStrategy);

      // register strategy
      await testSwapIntegration.updateSwapStrategies(
        strangeStrategy,
        true,
      );

      await expect(testSwapIntegration.connect(alice).allocate(strangeStrategy, amount))
        .to.be.revertedWithCustomError(testSwapIntegration, "NotFromSuperStrategy")
        .withArgs(strangeStrategy);

      await testSwapIntegration.updateSuperformStrategies(
        strangeStrategy,
        true,
      );

      // OK
      await testSwapIntegration.connect(alice).allocate(strangeStrategy, amount);
    });

    it("allocation", async function () {
      const { testSwapIntegration, swapSuperStrategy, usdt, usdc, erc4626Vault, superUSDC, signers } = await loadFixture(getMockedIntegrations);
      const { alice } = signers;

      const initialSVaultAmount = await usdc.balanceOf(erc4626Vault);
      const amount = parseUnits("100", 6);

      expect(await superUSDC.balanceOf(alice)).to.equal(0);

      await usdt.connect(alice).approve(testSwapIntegration, amount);
      await testSwapIntegration.connect(alice).allocate(swapSuperStrategy, amount);

      expect(await usdt.allowance(alice, testSwapIntegration)).to.equal(0);
      expect(await usdc.balanceOf(erc4626Vault)).to.equal(amount + initialSVaultAmount);
      expect(await superUSDC.balanceOf(alice)).to.equal(amount);
    });

    it("exit", async function () {
      const { testSwapIntegration, swapSuperStrategy, usdt, usdc, erc4626Vault, curvePool, superUSDC, signers } = await loadFixture(getMockedIntegrations);
      const { alice } = signers;

      const amount = parseUnits("300", 6);

      await usdt.connect(alice).approve(testSwapIntegration, amount);
      await testSwapIntegration.connect(alice).allocate(swapSuperStrategy, amount);

      await superUSDC.connect(alice).approve(testSwapIntegration, amount);
      const exitTx = testSwapIntegration.connect(alice).exit(swapSuperStrategy, amount);

      expect(exitTx).to.changeTokenBalance(superUSDC, alice, -amount);
      expect(exitTx).to.changeTokenBalances(usdt, [curvePool, alice], [-amount, amount]);
      expect(exitTx).to.changeTokenBalances(usdc, [erc4626Vault, curvePool], [-amount, amount]);
    });

    it("slippage tolerance", async function () {
      const { testSwapIntegration, swapSuperStrategy, curveRouter, usdt, usdc, erc4626Vault, curvePool, superUSDC, signers } = await loadFixture(getMockedIntegrations);
      const { alice } = signers;

      const amount = parseUnits("300", 6);

      // set rate in the pool to 0.95
      const rate = parseEther("0.95");
      await curvePool.setRate(rate);

      await usdt.connect(alice).approve(testSwapIntegration, amount);
      await expect(testSwapIntegration.connect(alice).allocate(swapSuperStrategy, amount))
        .to.be.revertedWithCustomError(curveRouter, "Slippage");

      await swapSuperStrategy.setSlippage(499); // 4.99% slippage tolerance

      // still should revert, 4.99% < 5%
      await expect(testSwapIntegration.connect(alice).allocate(swapSuperStrategy, amount))
        .to.be.revertedWithCustomError(curveRouter, "Slippage");

      await swapSuperStrategy.setSlippage(500);

      const allocTx = testSwapIntegration.connect(alice).allocate(swapSuperStrategy, amount);

      expect(allocTx).to.changeTokenBalances(usdt, [curvePool, alice], [amount, -amount]);

      const expectedAmount = (amount * rate) / parseEther("1");
      expect(allocTx).to.changeTokenBalances(usdc, [erc4626Vault, curvePool], [expectedAmount, -expectedAmount]);
      expect(allocTx).to.changeTokenBalance(superUSDC, alice, expectedAmount);
    });
  });

  describe("Curve - Swap Strategy", function () {
    it("swap strategy is also a superform strategy", async function () {
      const { hyperStaking, swapSuperStrategy } = await loadFixture(deployHyperStaking);
      const { testUSDC, testUSDT, diamond, hyperFactory, hyperlaneHandler } = hyperStaking;

      const superformId = await hyperStaking.superformFactory.vaultToSuperforms(hyperStaking.superVault, 0);

      expect(await swapSuperStrategy.DIAMOND()).to.equal(diamond);
      expect(await swapSuperStrategy.SUPERFORM_ID()).to.equal(superformId);
      expect(await swapSuperStrategy.SUPERFORM_INPUT_TOKEN()).to.equal(testUSDC);

      const revenueAsset = await swapSuperStrategy.revenueAsset();
      expect(revenueAsset).to.not.equal(ZeroAddress);

      // VaultInfo
      expect((await hyperFactory.vaultInfo(swapSuperStrategy)).enabled).to.deep.equal(true);
      expect((await hyperFactory.vaultInfo(swapSuperStrategy)).direct).to.deep.equal(false);
      expect((await hyperFactory.vaultInfo(swapSuperStrategy)).stakeCurrency).to.deep.equal([testUSDT.target]); // USDT and not USDC
      expect((await hyperFactory.vaultInfo(swapSuperStrategy)).strategy).to.equal(swapSuperStrategy);
      expect((await hyperFactory.vaultInfo(swapSuperStrategy)).revenueAsset).to.equal(revenueAsset);

      const [exists, vaultShares] = await hyperlaneHandler.getRouteInfo(swapSuperStrategy);
      expect(exists).to.equal(true);
      expect(vaultShares).to.not.equal(ZeroAddress);
    });

    it("staking using swap strategy", async function () {
      const { hyperStaking, swapSuperStrategy, vaultShares, superUSDC, signers } = await loadFixture(deployHyperStaking);
      const { testUSDC, testUSDT, erc4626Vault, curvePool, deposit, defaultWithdrawDelay, allocation, hyperFactory, lockbox, hyperlaneHandler, realAssets } = hyperStaking;
      const { alice } = signers;

      const amount = parseUnits("2000", 6);

      await testUSDT.connect(alice).approve(deposit, amount);
      const depositTx = deposit.connect(alice).stakeDeposit(swapSuperStrategy, alice, amount);

      await expect(depositTx).to.changeTokenBalances(testUSDT,
        [alice, curvePool], [-amount, amount]);

      // USDC/USDT 1:1 rate
      await expect(depositTx).to.changeTokenBalances(testUSDC,
        [curvePool, erc4626Vault], [-amount, amount]);

      expect(await superUSDC.totalSupply()).to.equal(amount);
      expect(await superUSDC.balanceOf(allocation)).to.equal(amount);

      // there should be no allowance for the swap strategy,
      // (allocate gives it, but is used indirectly)
      expect(await testUSDT.allowance(deposit, swapSuperStrategy)).to.eq(0);

      const [enabled] = await hyperFactory.vaultInfo(swapSuperStrategy, alice);
      expect(enabled).to.be.eq(true);

      const routeInfo = await hyperlaneHandler.getRouteInfo(swapSuperStrategy);
      expect(routeInfo.vaultShares).to.be.eq(vaultShares);

      // lpToken on the Lumia chain side
      const rwaBalance = await vaultShares.balanceOf(alice);
      expect(rwaBalance).to.be.eq(amount);

      await vaultShares.connect(alice).approve(realAssets, rwaBalance);
      const expectedUnlock = await shared.getCurrentBlockTimestamp() + defaultWithdrawDelay;

      const redeemTx = realAssets.connect(alice).redeem(swapSuperStrategy, alice, alice, rwaBalance);

      await expect(redeemTx)
        .to.changeTokenBalance(vaultShares, alice, -rwaBalance);

      await expect(redeemTx)
        .to.changeTokenBalances(testUSDC,
          [curvePool, erc4626Vault], [amount, -amount]);

      await expect(redeemTx)
        .to.changeTokenBalances(testUSDT,
          [lockbox, curvePool], [amount, -amount]);

      await time.setNextBlockTimestamp(expectedUnlock);
      await expect(deposit.connect(alice).claimWithdraw(swapSuperStrategy, alice))
        .to.changeTokenBalances(testUSDT,
          [alice, lockbox],
          [amount, -amount],
        );

      expect(await testUSDT.allowance(deposit, swapSuperStrategy)).to.eq(0);

      expect(await vaultShares.balanceOf(alice)).to.be.eq(0);
    });
  });
});
