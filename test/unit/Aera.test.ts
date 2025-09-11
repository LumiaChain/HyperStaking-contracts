import { expect } from "chai";
import { ethers, ignition } from "hardhat";
import { time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { parseUnits, Log } from "ethers";
import * as shared from "../shared";
import { TokenDetailsStruct } from "../../typechain-types/contracts/external/aera/Provisioner";

import GauntletMockModule from "../../ignition/modules/test/GauntletMock";

async function getMockedGauntlet() {
  const [owner, feeRecipient, alice] = await ethers.getSigners();

  const testUSDC = await shared.deloyTestERC20("Test USD Coin", "tUSDC", 6);
  await testUSDC.mint(alice.address, parseUnits("1000000", 6));

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

  // Register vault in the PriceAndFeeCalculator (idempotent)
  await aeraPriceAndFeeCalculator.connect(owner).registerVault();

  // Set thresholds and initial price so pricing is "active"
  await aeraPriceAndFeeCalculator.connect(owner).setThresholds(
    await aeraMultiDepositorVault.getAddress(),
    0,          // minPriceToleranceBps
    20_000,     // maxPriceToleranceBps (200%) to be safe for tests
    0,          // minUpdateInterval (disable for tests)
    120,        // maxPriceAge seconds (1 day) – or whatever your API expects
    30,         // maxUpdateDelayDays (lib-dependent; keep permissive)
  );

  // Set initial unit price to 1 USDC per unit
  await aeraPriceAndFeeCalculator.connect(owner).setInitialPrice(
    await aeraMultiDepositorVault.getAddress(),
    parseUnits("1", 6), // unit price in numeraire (USDC has 6 decimals)
    await shared.getCurrentBlockTimestamp(),
  );

  // Enable async deposits for USDC
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
      expect(await aeraProvisioner.authority()).to.not.equal(ethers.ZeroAddress);

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

  describe("Strategy", function () {
  });
});
