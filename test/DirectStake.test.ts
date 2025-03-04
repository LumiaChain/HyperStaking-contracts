import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { parseEther } from "ethers";

import * as shared from "./shared";

async function deployHyperStaking() {
  const [owner, stakingManager, vaultManager, strategyManager, bob, alice] = await ethers.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testUSDC = await shared.deloyTestERC20("Test USDC", "tUSDC", 6); // 6 decimal places
  const erc4626Vault = await shared.deloyTestERC4626Vault(testUSDC);

  // --------------------- Hyperstaking Diamond --------------------

  const { diamond, deposit, hyperFactory, rwaUSD } = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Apply Strategies --------------------

  const directStakeStrategy = await shared.createDirectStakeStrategy(
    diamond, await testUSDC.getAddress(),
  );

  await hyperFactory.connect(vaultManager).addDirectStrategy(
    directStakeStrategy,
    rwaUSD,
  );

  // ----------------------------------------

  /* eslint-disable object-property-newline */
  return {
    diamond, // diamond
    deposit, hyperFactory, rwaUSD, // diamond facets
    testUSDC, directStakeStrategy, // test contracts
    owner, stakingManager, vaultManager, strategyManager, alice, bob, // addresses
  };
  /* eslint-enable object-property-newline */
}

describe("Direct Stake", function () {
  it("only direct stake strategy should be allowed for direct staking", async function () {
    const { diamond, deposit, hyperFactory, testUSDC, directStakeStrategy, alice, vaultManager } = await loadFixture(deployHyperStaking);

    // adding new non-direct stake strategy
    const reserveAssetPrice = parseEther("2");
    const reserveStrategy = await shared.createReserveStrategy(
      diamond, shared.nativeTokenAddress, await testUSDC.getAddress(), reserveAssetPrice,
    );

    await hyperFactory.connect(vaultManager).addStrategy(
      reserveStrategy,
      "eth reserve vault1",
      "rUSD",
      parseEther("0"),
    );

    const stakeAmount = parseEther("1000");
    await expect(deposit.directStakeDeposit(reserveStrategy, stakeAmount, alice))
      .to.be.revertedWithCustomError(deposit, "NotDirectDeposit")
      .withArgs(reserveStrategy.target);

    await testUSDC.approve(deposit, stakeAmount);
    await expect(deposit.directStakeDeposit(directStakeStrategy, stakeAmount, alice))
      .to.not.reverted;

    // TODO DirectRwaMint
    // TODO DirectRwaRedeem
  });

  it("direct stake strategy should mint rwaUSD in 1:1 ratio", async function () {
    const { deposit, testUSDC, rwaUSD, directStakeStrategy, alice } = await loadFixture(deployHyperStaking);

    const stakeAmount = parseEther("500");

    await testUSDC.approve(deposit, stakeAmount);
    await deposit.directStakeDeposit(directStakeStrategy, stakeAmount, alice);

    expect(await rwaUSD.balanceOf(alice)).to.equal(stakeAmount);
  });

  // TODO check bridged state after stake
  // TODO check bridged state after redeem getUserBridged

  // TODO creating strategy route
  // TODO get route info, hmh other?

  // TODO set rwa asset
  // TODO get rwa asset
});
