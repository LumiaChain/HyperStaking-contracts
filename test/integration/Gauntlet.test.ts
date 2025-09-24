import { loadFixture, impersonateAccount, stopImpersonatingAccount } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers, ignition } from "hardhat";
import { parseEther, parseUnits } from "ethers";

import { expect } from "chai";
import * as shared from "../shared";

import GauntletStrategyModule from "../../ignition/modules/GauntletStrategy";

const AERA_PROVISIONER_ADDRESS = "0x18CF8d963E1a727F9bbF3AEffa0Bd04FB4dBdA07";

const USDC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
const GTUSDA_ADDRESS = "0x000000000001CdB57E58Fa75Fe420a0f4D6640D5"; // gtUSDa

// Common holder for USDC (stake token) and gtUSDa (vault units)
const WHALE_ADDRESS = "0xEE3D1Fae97a51bFB7effB77E2DD5E053B895D4D6";

describe("Test Gauntlet Strategy", function () {
  async function getAeraIntegration() {
    const signers = await shared.getSigners();

    const usdc = await ethers.getContractAt(shared.fullyQualifiedIERC20, USDC_ADDRESS);
    const gtUSDa = await ethers.getContractAt("MultiDepositorVault", GTUSDA_ADDRESS);

    // give whale 1 ETH
    await ethers.provider.send("hardhat_setBalance", [
      WHALE_ADDRESS,
      "0x0de0b6b3a7640000", // 1 ETH in hex (1e18)
    ]);

    // create strategy
    const { gauntletStrategy } = await ignition.deploy(GauntletStrategyModule, {
      parameters: {
        GauntletStrategyModule: {
          // using owner as a diamond
          diamond: signers.owner.address,
          stakeToken: USDC_ADDRESS,
          aeraProvisioner: AERA_PROVISIONER_ADDRESS,
        },
      },
    });

    await impersonateAccount(WHALE_ADDRESS);
    const whaleSigner = await ethers.getSigner(WHALE_ADDRESS);

    await usdc.connect(whaleSigner).transfer(signers.owner, parseUnits("1000", 6));
    await gtUSDa.connect(whaleSigner).transfer(gauntletStrategy, parseEther("1000"));

    await stopImpersonatingAccount(WHALE_ADDRESS);

    const lumiaGtUSDAAddress = await gauntletStrategy.LUMIA_GTUSDA();
    const lumiaGtUSDA = await ethers.getContractAt(shared.fullyQualifiedIERC20, lumiaGtUSDAAddress);

    /* eslint-disable object-property-newline */
    return {
      gauntletStrategy, // strategy
      usdc, gtUSDa, lumiaGtUSDA, // tokens
      signers, // signers
    };
    /* eslint-disable object-property-newline */
  }

  it("allocation: dont revert, emits deposit hash, escrows USDC on Provisioner, updates recordedAllocation", async function () {
    const { gauntletStrategy, usdc, signers } = await loadFixture(getAeraIntegration);
    const { owner } = signers;

    const amount = parseUnits("250", 6);

    const provUSDCBefore = await usdc.balanceOf(AERA_PROVISIONER_ADDRESS);

    // owner acts as the Diamond (you set DIAMOND = owner in module params)
    await usdc.connect(owner).approve(gauntletStrategy, amount);

    const reqId = 1;
    const tx = await gauntletStrategy.connect(owner).requestAllocation(reqId, amount, owner.address);

    // non-zero deposit hash
    const depositHash = await shared.getEventArg(tx, "AeraAsyncDepositHash", gauntletStrategy);
    expect(depositHash).to.not.equal("0x" + "00".repeat(32));

    // SDC moved owner -> Provisioner (escrow)
    const provUSDCAfter = await usdc.balanceOf(AERA_PROVISIONER_ADDRESS);
    expect(provUSDCAfter).to.be.greaterThan(provUSDCBefore);

    // recorded allocation (units > 0)
    expect(await gauntletStrategy.recordedAllocation(reqId)).to.be.gt(0n);
  });

  it("request exit (fork): claim wrapper, transfer to strategy, emit redeem hash, set recordedExit & allowance", async function () {
    const { gauntletStrategy, usdc, lumiaGtUSDA, signers } = await loadFixture(getAeraIntegration);
    const { owner } = signers;

    // --- stake via strategy → emits deposit hash & escrows USDC on Provisioner ---
    const amount = parseUnits("250", 6);
    await usdc.connect(owner).approve(gauntletStrategy, amount);

    const allocReqId = 1;
    const stakeTx = await gauntletStrategy.connect(owner).requestAllocation(allocReqId, amount, owner);

    const depositHash = await shared.getEventArg(stakeTx, "AeraAsyncDepositHash", gauntletStrategy);
    expect(depositHash).to.not.equal("0x" + "00".repeat(32));

    // --- fast-forward to be able to claim (readyAt = block + deadlineOffset) ---
    const cfg = await gauntletStrategy.aeraConfig();
    await ethers.provider.send("evm_increaseTime", [Number(cfg.deadlineOffset)]);
    await ethers.provider.send("evm_mine", []);

    // --- claim allocation → mints wrapper to owner ---
    await gauntletStrategy.connect(owner).claimAllocation([allocReqId], owner);

    const shares = await lumiaGtUSDA.balanceOf(owner);
    expect(shares).to.be.gt(0n);

    // approve the strategy to pull wrapper on exit
    await lumiaGtUSDA.connect(owner).approve(gauntletStrategy, shares);

    // --- request exit using lumiaGtUSDA ---
    const exitReqId = 2;
    const exitTx = await gauntletStrategy.connect(owner).requestExit(exitReqId, shares, owner);

    // redeem hash emitted
    const redeemHash = await shared.getEventArg(exitTx, "AeraAsyncRedeemHash", gauntletStrategy);
    expect(redeemHash).to.not.equal("0x" + "00".repeat(32));

    // wrapper moved owner -> strategy (held until settlement/claim)
    expect(await lumiaGtUSDA.balanceOf(owner)).to.eq(0n);
    expect(await lumiaGtUSDA.balanceOf(await gauntletStrategy.getAddress())).to.eq(shares);

    // recordedExit (USDC out)
    expect(await gauntletStrategy.recordedExit(exitReqId)).to.be.gt(0n);

    // no settlement on fork; local mock suite handles solve & claim
  });
});
