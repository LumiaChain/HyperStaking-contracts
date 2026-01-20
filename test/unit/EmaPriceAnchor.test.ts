import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { parseEther, parseUnits } from "ethers";
import * as shared from "../shared";

describe("LibEmaPriceAnchor", function () {
  async function deployFixture() {
    const [owner, alice] = await ethers.getSigners();

    // Deploy test ERC20 tokens
    const usdc = await shared.deployTestERC20("USDC", "USDC", 6);
    const usdt = await shared.deployTestERC20("USDT", "USDT", 6);

    // Deploy test proxy contract
    const TestEmaPriceAnchor = await ethers.getContractFactory("TestEmaPriceAnchor");
    const ema = await TestEmaPriceAnchor.deploy();

    return { ema, usdc, usdt, owner, alice };
  }

  describe("Configuration", function () {
    it("should configure anchor successfully", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      await ema.configure(
        usdc.target,
        usdt.target,
        true, // enabled
        100, // 1% deviation
        2000, // 20% alpha
        parseUnits("1000", 6),  // 1000 volume threshold
      );

      const anchor = await ema.getAnchor(usdc.target, usdt.target);
      expect(anchor.tokenIn).to.equal(usdc.target);
      expect(anchor.tokenOut).to.equal(usdt.target);
      expect(anchor.enabled).to.equal(true);
      expect(anchor.deviationBps).to.equal(100);
      expect(anchor.emaAlphaBps).to.equal(2000);
      expect(anchor.volumeThreshold).to.equal(parseUnits("1000", 6));
      expect(anchor.emaPrice).to.equal(0); // not initialized yet
    });

    it("should revert on bad parameters", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      // Bad deviation (> 10000)
      await expect(
        ema.configure(usdc.target, usdt.target, true, 10001, 2000, 1000n),
      ).to.be.revertedWithCustomError(ema, "BadBps");

      // Bad alpha (0)
      await expect(
        ema.configure(usdc.target, usdt.target, true, 100, 0, 1000n),
      ).to.be.revertedWithCustomError(ema, "BadAlpha");

      // Bad alpha (> 10000)
      await expect(
        ema.configure(usdc.target, usdt.target, true, 100, 10001, 1000n),
      ).to.be.revertedWithCustomError(ema, "BadAlpha");

      // Bad tokens (same token)
      await expect(
        ema.configure(usdc.target, usdc.target, true, 100, 2000, 1000n),
      ).to.be.revertedWithCustomError(ema, "BadTokens");
    });

    it("should revert when using unconfigured anchor", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      const amountIn = parseUnits("100", 6);
      const spotOut = parseUnits("99", 6);

      // trying to use unconfigured anchor should revert
      await expect(
        ema.guardedOut(usdc.target, usdt.target, amountIn, spotOut, 0),
      ).to.be.revertedWithCustomError(ema, "AnchorNotConfigured")
        .withArgs(usdc.target, usdt.target);

      await expect(
        ema.recordExecution(usdc.target, usdt.target, amountIn, spotOut),
      ).to.be.revertedWithCustomError(ema, "AnchorNotConfigured")
        .withArgs(usdc.target, usdt.target);
    });

    it("should revert when using disabled anchor", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      // configure but disabled
      await ema.configure(usdc.target, usdt.target, false, 100, 2000, 1000n);

      const amountIn = parseUnits("100", 6);
      const spotOut = parseUnits("99", 6);

      await expect(
        ema.guardedOut(usdc.target, usdt.target, amountIn, spotOut, 0),
      ).to.be.revertedWithCustomError(ema, "AnchorDisabled")
        .withArgs(usdc.target, usdt.target);

      await expect(
        ema.recordExecution(usdc.target, usdt.target, amountIn, spotOut),
      ).to.be.revertedWithCustomError(ema, "AnchorDisabled")
        .withArgs(usdc.target, usdt.target);
    });
  });

  describe("Bootstrap Phase", function () {
    it("should return spot quote when uninitialized", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      await ema.configure(usdc.target, usdt.target, true, 100, 2000, 1000n);

      const amountIn = parseUnits("100", 6);
      const spotOut = parseUnits("99", 6); // slightly worse than 1:1

      // not initialized, should return spot
      const result = await ema.guardedOut(
        usdc.target,
        usdt.target,
        amountIn,
        spotOut,
        0, // no slippage
      );

      expect(result).to.equal(spotOut);
      expect(await ema.isInitialized(usdc.target, usdt.target)).to.equal(false);
    });

    it("should initialize EMA on first execution", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      await ema.configure(usdc.target, usdt.target, true, 100, 2000, 1000n);

      const amountIn = parseUnits("100", 6);
      const amountOut = parseUnits("99", 6);

      await ema.recordExecution(usdc.target, usdt.target, amountIn, amountOut);

      expect(await ema.isInitialized(usdc.target, usdt.target)).to.equal(true);

      const anchor = await ema.getAnchor(usdc.target, usdt.target);
      // emaPrice = (99 * 1e18) / 100 = 0.99e18
      expect(anchor.emaPrice).to.equal(parseEther("0.99"));
    });
  });

  describe("EMA Protection", function () {
    it("should clamp spot quote within deviation band", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      await ema.configure(usdc.target, usdt.target, true, 100, 2000, 1000n); // 1% deviation

      // initialize EMA at 1:1
      const initAmount = parseUnits("100", 6);
      await ema.recordExecution(usdc.target, usdt.target, initAmount, initAmount);

      const amountIn = parseUnits("100", 6);

      // spot quote is 0.97 (3% worse) - should be clamped to 0.99 (1% deviation)
      const badSpot = parseUnits("97", 6);
      const result = await ema.guardedOut(usdc.target, usdt.target, amountIn, badSpot, 0);

      // expected: emaOut = 100, deviation = 1%, so min = 99
      expect(result).to.equal(parseUnits("99", 6));
    });

    it("should accept spot quote within deviation band", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      await ema.configure(usdc.target, usdt.target, true, 100, 2000, 1000n); // 1% deviation

      // initialize EMA at 1:1
      const initAmount = parseUnits("100", 6);
      await ema.recordExecution(usdc.target, usdt.target, initAmount, initAmount);

      const amountIn = parseUnits("100", 6);

      // spot quote is 0.995 (0.5% worse) - within 1% band
      const goodSpot = parseUnits("99.5", 6);
      const result = await ema.guardedOut(usdc.target, usdt.target, amountIn, goodSpot, 0);

      // returns spot since it's within acceptable bounds (99.5)
      expect(result).to.equal(parseUnits("99.5", 6));
    });

    it("should apply slippage on top of EMA protection", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      await ema.configure(usdc.target, usdt.target, true, 100, 2000, 1000n);

      // initialize at 1:1
      const initAmount = parseUnits("100", 6);
      await ema.recordExecution(usdc.target, usdt.target, initAmount, initAmount);

      const amountIn = parseUnits("100", 6);
      const spotOut = parseUnits("100", 6); // perfect 1:1

      // apply 0.5% slippage
      const result = await ema.guardedOut(usdc.target, usdt.target, amountIn, spotOut, 50);

      // 100 * (10000 - 50) / 10000 = 99.5
      expect(result).to.equal(parseUnits("99.5", 6));
    });
  });

  describe("Volume Weighting", function () {
    it("should not update EMA for trades below threshold", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      const threshold = parseUnits("1000", 6);
      await ema.configure(usdc.target, usdt.target, true, 100, 2000, threshold);

      // initialize at 1:1
      const largeAmount = parseUnits("1000", 6);
      await ema.recordExecution(usdc.target, usdt.target, largeAmount, largeAmount);

      const initialAnchor = await ema.getAnchor(usdc.target, usdt.target);
      const initialPrice = initialAnchor.emaPrice;

      // small trade (below threshold) with bad price
      const smallAmount = parseUnits("50", 6);
      const badPrice = parseUnits("80", 6); // 0.8:1 ratio
      await ema.recordExecution(usdc.target, usdt.target, smallAmount, badPrice);

      const afterAnchor = await ema.getAnchor(usdc.target, usdt.target);

      // EMA should NOT change
      expect(afterAnchor.emaPrice).to.equal(initialPrice);
    });

    it("should update EMA for trades above threshold", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      const threshold = parseUnits("1000", 6);
      await ema.configure(usdc.target, usdt.target, true, 100, 2000, threshold);

      // initialize at 1:1
      const largeAmount = parseUnits("1000", 6);
      await ema.recordExecution(usdc.target, usdt.target, largeAmount, largeAmount);

      const initialAnchor = await ema.getAnchor(usdc.target, usdt.target);
      expect(initialAnchor.emaPrice).to.equal(parseEther("1"));

      // large trade with slightly different price
      const newPrice = parseUnits("990", 6); // 0.99:1
      await ema.recordExecution(usdc.target, usdt.target, largeAmount, newPrice);

      const afterAnchor = await ema.getAnchor(usdc.target, usdt.target);

      // EMA should update: newEma = 1.0 * 0.8 + 0.99 * 0.2 = 0.998
      expect(afterAnchor.emaPrice).to.equal(parseEther("0.998"));
    });
  });

  describe("Guard and Record", function () {
    it("separate guard and record calls", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);
      const threshold = parseUnits("100", 6);
      await ema.configure(usdc.target, usdt.target, true, 100, 2000, threshold);

      const amountIn = parseUnits("1000", 6);
      const spotOut = parseUnits("1000", 6);

      // use guardedOut to get protected quote
      const minOut = await ema.guardedOut(usdc.target, usdt.target, amountIn, spotOut, 50);
      expect(minOut).to.equal(parseUnits("995", 6));

      // then record execution separately
      await ema.recordExecution(usdc.target, usdt.target, amountIn, spotOut);

      // should be initialized
      expect(await ema.isInitialized(usdc.target, usdt.target)).to.equal(true);
    });
  });

  describe("Edge Cases", function () {
    it("should handle zero quote error", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      await ema.configure(usdc.target, usdt.target, true, 100, 2000, 1000n);

      await expect(
        ema.guardedOut(usdc.target, usdt.target, 100n, 0n, 0),
      ).to.be.revertedWithCustomError(ema, "ZeroQuote");
    });

    it("should return 0 for zero amountIn", async function () {
      const { ema, usdc, usdt } = await loadFixture(deployFixture);

      await ema.configure(usdc.target, usdt.target, true, 100, 2000, 1000n);

      // initialize first
      await ema.recordExecution(usdc.target, usdt.target, 100n, 100n);

      const result = await ema.guardedOut(usdc.target, usdt.target, 0n, 100n, 0);
      expect(result).to.equal(0);
    });
  });
});
