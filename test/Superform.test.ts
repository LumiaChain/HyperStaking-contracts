import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { ethers, ignition, network } from "hardhat";
import { Signer, Contract, parseUnits, ZeroAddress } from "ethers";

import SuperformStrategyModule from "../ignition/modules/SuperformStrategy";

import * as shared from "./shared";
import { SingleDirectSingleVaultStateReqStruct } from "../typechain-types/contracts/external/superform/core/BaseRouter";
import { SuperformRouter, BaseForm, SuperPositions } from "../typechain-types";
import { IERC20 } from "../typechain-types/@openzeppelin/contracts/token/ERC20";

async function getMockedSuperform() {
  const [superManager, alice] = await ethers.getSigners();

  const testUSDC = await shared.deloyTestERC20("Test USD Coin", "tUSDC", 6);
  const erc4626Vault = await shared.deloyTestERC4626Vault(testUSDC);
  await testUSDC.mint(alice.address, parseUnits("1000000", 6));

  // --------------------

  const {
    superformFactory, superformRouter, superVault, superPositions,
  } = await shared.deploySuperformMock(erc4626Vault);

  // --------------------

  const superformId = await superformFactory.vaultToSuperforms(superVault, 0);
  const subSuperformId = await superVault.superformIds(0);

  const [superformAddress,,] = await superformFactory.getSuperform(superformId);
  const superform = await ethers.getContractAt("BaseForm", superformAddress);

  // --------------------

  return {
    superformFactory, superformRouter, superVault, superPositions, superformId, subSuperformId, superform, superManager, testUSDC, erc4626Vault, alice,
  };
}

const registerAERC20 = async (
  superformRouter: SuperformRouter,
  superformId: bigint,
  superform: BaseForm,
  superPositions: SuperPositions,
  testUSDC: Contract,
): Promise<IERC20> => {
  // to register aERC20 we need to deposit some amount first

  const [owner] = await ethers.getSigners();
  const amount = parseUnits("1", 6);
  const maxSlippage = 50n; // 0.5%
  const outputAmount = await superform.previewDepositTo(amount);

  await testUSDC.approve(superformRouter, amount);
  const routerReq: SingleDirectSingleVaultStateReqStruct = {
    superformData: {
      superformId,
      amount,
      outputAmount,
      maxSlippage,
      liqRequest: {
        txData: "0x",
        token: testUSDC,
        interimToken: ZeroAddress,
        bridgeId: 1,
        liqDstChainId: 0,
        nativeAmount: 0,
      },
      permit2data: "0x",
      hasDstSwap: false,
      retain4626: false,
      receiverAddress: owner,
      receiverAddressSP: owner,
      extraFormData: "0x",
    },
  };

  await superformRouter.singleDirectSingleVaultDeposit(routerReq);

  // actual token registration
  await superPositions.registerAERC20(superformId);

  return ethers.getContractAt(
    "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
    await superPositions.getERC20TokenAddress(superformId),
  ) as unknown as IERC20;
};

async function deployHyperStaking() {
  const signers = await shared.getSigners();

  // -------------------- Deploy Tokens --------------------

  const testUSDC = await shared.deloyTestERC20("Test USDC", "tUSDC", 6); // 6 decimal places
  const erc4626Vault = await shared.deloyTestERC4626Vault(testUSDC);

  await testUSDC.mint(signers.alice.address, parseUnits("1000000", 6));

  // -------------------- Hyperstaking Diamond --------------------

  const hyperStaking = await shared.deployTestHyperStaking(0n, erc4626Vault);

  // -------------------- Apply Strategies --------------------

  const { superformStrategy } = await ignition.deploy(SuperformStrategyModule, {
    parameters: {
      SuperformStrategyModule: {
        diamond: await hyperStaking.diamond.getAddress(),
        superVault: await hyperStaking.superVault.getAddress(),
        stakeToken: await testUSDC.getAddress(),
      },
    },
  });

  const superformId = await hyperStaking.superformFactory.vaultToSuperforms(hyperStaking.superVault, 0);

  // -------

  const superformFactory = await ethers.getContractAt("SuperformFactory", await hyperStaking.superformIntegration.superformFactory());
  const superformRouter = await ethers.getContractAt("SuperformRouter", await hyperStaking.superformIntegration.superformRouter());
  const superPositions = await ethers.getContractAt("SuperPositions", await hyperStaking.superformIntegration.superPositions());
  const superVault = hyperStaking.superVault;

  const [superformAddress,,] = await superformFactory.getSuperform(superformId);
  const superform = await ethers.getContractAt("BaseForm", superformAddress);

  const aerc20 = await registerAERC20(superformRouter, superformId, superform, superPositions, testUSDC);

  // --------------------

  const vaultTokenName = "Lumia USD Superform Position";
  const vaultTokenSymbol = "lspUSD";

  await hyperStaking.hyperFactory.connect(signers.vaultManager).addStrategy(
    superformStrategy,
    vaultTokenName,
    vaultTokenSymbol,
  );

  await hyperStaking.superformIntegration.connect(signers.strategyManager).updateSuperformStrategies(
    superformStrategy,
    true,
  );

  // -------------------- Hyperlane Handler --------------------

  const { principalToken, vaultShares } = await shared.getDerivedTokens(
    hyperStaking.hyperlaneHandler,
    await superformStrategy.getAddress(),
  );

  // --------------------

  /* eslint-disable object-property-newline */
  return {
    hyperStaking, // HyperStaking deployment
    testUSDC, superformStrategy, erc4626Vault, aerc20, principalToken, vaultShares, // test contracts
    superform, superVault, superformFactory, superPositions, superformRouter, superformId, // superform
    vaultTokenName, vaultTokenSymbol, // values
    signers, // signers
  };
  /* eslint-enable object-property-newline */
}

describe("Superform", function () {
  describe("Mock", function () {
    const superUSDCDeposit = async (
      amount: bigint,
      receiver: Signer,
      outputAmount?: bigint,
      maxSlippage: bigint = 50n, // 0.5%
    ) => {
      const { superformRouter, superform, testUSDC, superformId } = await loadFixture(getMockedSuperform);

      if (!outputAmount) {
        outputAmount = await superform.previewDepositTo(amount);
      }

      await testUSDC.connect(receiver).approve(superformRouter, amount);
      const routerReq: SingleDirectSingleVaultStateReqStruct = {
        superformData: {
          superformId,
          amount,
          outputAmount,
          maxSlippage,
          liqRequest: {
            txData: "0x",
            token: testUSDC,
            interimToken: ZeroAddress,
            bridgeId: 1,
            liqDstChainId: 0,
            nativeAmount: 0,
          },
          permit2data: "0x",
          hasDstSwap: false,
          retain4626: false,
          receiverAddress: receiver,
          receiverAddressSP: receiver,
          extraFormData: "0x",
        },
      };

      await superformRouter.connect(receiver).singleDirectSingleVaultDeposit(routerReq);
    };

    it("overall tests of the mock", async function () {
      const { superformFactory, superVault, superPositions, testUSDC, erc4626Vault, alice } = await loadFixture(getMockedSuperform);

      const superformId = await superVault.superformIds(0);
      expect(await superformFactory.isSuperform(superformId)).to.equal(true);
      expect(await superformFactory.vaultToSuperforms(erc4626Vault.target, 0)).to.equal(superformId);

      expect(await superPositions.name()).to.equal("Super Test Positions");
      expect(await superPositions.symbol()).to.equal("STP");
      expect(await superPositions.dynamicURI()).to.equal("dynamicURI");

      const [superformAddress, formId, chainId] = await superformFactory.getSuperform(superformId);

      expect(formId).to.equal(1);
      expect(chainId).to.equal(network.config.chainId);

      const superform = await ethers.getContractAt("ERC4626Form", superformAddress);

      expect(await superform.getVaultName()).to.equal(await erc4626Vault.name());
      expect(await superform.getVaultSymbol()).to.equal(await erc4626Vault.symbol());

      expect(await superform.vault()).to.equal(erc4626Vault.target);
      expect(await superform.asset()).to.equal(testUSDC.target);

      expect(await superPositions.balanceOf(alice.address, superformId)).to.equal(0);
      expect(await superPositions.totalSupply(superformId)).to.equal(0);
    });

    it("it should be possible to deposit USDC using superRouter", async function () {
      const { superform, superformId, superPositions, alice } = await loadFixture(getMockedSuperform);

      // deposit amount
      const amount = parseUnits("100", 6);

      const maxSlippage = 100n; // 1%
      const outputAmount = await superform.previewDepositTo(amount);

      await superUSDCDeposit(amount, alice, outputAmount, maxSlippage);

      const outputAmountSlipped = outputAmount * (10000n - maxSlippage) / 10000n;
      expect(await superPositions.balanceOf(alice.address, superformId)).to.be.gt(outputAmountSlipped);
    });

    it("it should be possible to transmute superPositions to aERC20", async function () {
      const { superformId, superPositions, alice } = await loadFixture(getMockedSuperform);

      const amount = parseUnits("200", 6);

      await superUSDCDeposit(amount, alice);

      const balance = await superPositions.balanceOf(alice, superformId);

      await superPositions.registerAERC20(superformId);
      expect(await superPositions.aERC20Exists(superformId)).to.be.eq(true);

      const aerc20Address = await superPositions.getERC20TokenAddress(superformId);
      const aerc20 = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", aerc20Address);

      await superPositions.connect(alice).transmuteToERC20(alice, superformId, balance, alice);

      // after transmutimg the ERC115 balance should be 0
      expect(await superPositions.balanceOf(alice, superformId)).to.be.eq(0);

      // the same amount is in aERC20
      expect(await aerc20.balanceOf(alice)).to.be.eq(balance);

      // transmute back to ERC1155 (in 2 steps)
      await aerc20.connect(alice).approve(superPositions, balance - 100n);
      await superPositions.connect(alice).transmuteToERC1155A(alice, superformId, balance - 100n, alice);

      expect(await superPositions.balanceOf(alice, superformId)).to.be.eq(balance - 100n);
      expect(await aerc20.balanceOf(alice)).to.be.eq(100);

      await aerc20.connect(alice).approve(superPositions, 100n);
      await superPositions.connect(alice).transmuteToERC1155A(alice, superformId, 100, alice);

      expect(await superPositions.connect(alice).balanceOf(alice, superformId)).to.be.eq(balance);
      expect(await aerc20.balanceOf(alice)).to.be.eq(0);
    });

    it("it should be possible to withdraw superPositions", async function () {
      const { superformRouter, superform, superformId, superPositions, testUSDC, alice } = await loadFixture(getMockedSuperform);

      const amount = parseUnits("100", 6);
      await superUSDCDeposit(amount, alice);

      const superBalance = await superPositions.balanceOf(alice, superformId);
      expect(superBalance).to.be.gt(0);

      const maxSlippage = 100n; // 1%
      const outputAmount = await superform.previewWithdrawFrom(superBalance);

      const testUSDCBalanceBefore = await testUSDC.balanceOf(alice);

      const routerReq: SingleDirectSingleVaultStateReqStruct = {
        superformData: {
          superformId,
          amount: superBalance,
          outputAmount,
          maxSlippage,
          liqRequest: {
            txData: "0x",
            token: testUSDC,
            interimToken: ZeroAddress,
            bridgeId: 1,
            liqDstChainId: 0,
            nativeAmount: 0,
          },
          permit2data: "0x",
          hasDstSwap: false,
          retain4626: false,
          receiverAddress: alice,
          receiverAddressSP: alice,
          extraFormData: "0x",
        },
      };

      await superPositions.connect(alice).setApprovalForOne(superformRouter, superformId, superBalance);
      await superformRouter.connect(alice).singleDirectSingleVaultWithdraw(routerReq);

      expect(await superPositions.balanceOf(alice, superformId)).to.be.eq(0);
      expect(await testUSDC.balanceOf(alice)).to.be.gt(testUSDCBalanceBefore);
    });
  });

  describe("Strategy", function () {
    it("superform strategy with vault should be created and strategy registered on lumia side", async function () {
      const { hyperStaking, testUSDC, superformStrategy, superformId } = await loadFixture(deployHyperStaking);
      const { diamond, hyperFactory, hyperlaneHandler } = hyperStaking;

      expect(await superformStrategy.DIAMOND()).to.equal(diamond);
      expect(await superformStrategy.SUPERFORM_ID()).to.equal(superformId);
      expect(await superformStrategy.STAKE_TOKEN()).to.equal(testUSDC);

      const revenueAsset = await superformStrategy.revenueAsset(); // aERC20 from superpositons
      expect(revenueAsset).to.not.equal(ZeroAddress);

      // VaultInfo
      expect((await hyperFactory.vaultInfo(superformStrategy)).stakeCurrency).to.deep.equal([testUSDC.target]);
      expect((await hyperFactory.vaultInfo(superformStrategy)).strategy).to.equal(superformStrategy);
      expect((await hyperFactory.vaultInfo(superformStrategy)).revenueAsset).to.equal(revenueAsset);

      const [exists, vaultShares] = await hyperlaneHandler.getRouteInfo(superformStrategy);
      expect(exists).to.equal(true);
      expect(vaultShares).to.not.equal(ZeroAddress);
    });

    // TODO: when redeem and lumia shares are implemented
    // it("staking using superform strategy", async function () {
    //   const { hyperStaking, superformStrategy, testUSDC, erc4626Vault, vault, aerc20, signers } = await loadFixture(deployHyperStaking);
    //   const { deposit, allocation, hyperFactory, rwaUSD, realAssets } = hyperStaking;
    //   const { alice } = signers;
    //
    //   const amount = parseUnits("2000", 6);
    //
    //   await testUSDC.connect(alice).approve(deposit, amount);
    //   await expect(deposit.connect(alice).stakeDeposit(superformStrategy, alice, amount))
    //     .to.changeTokenBalances(testUSDC,
    //       [alice, erc4626Vault], [-amount, amount]);
    //
    //   expect(await aerc20.totalSupply()).to.equal(amount);
    //   expect(await aerc20.balanceOf(vault)).to.equal(amount);
    //
    //   const [enabled] = await hyperFactory.vaultInfo(superformStrategy, alice);
    //   expect(enabled).to.be.eq(true);
    //
    //   const [vaultToken] = await allocation.stakeInfo(superformStrategy, alice);
    //   expect(vaultToken).to.be.eq(vault.target);
    //
    //   // lpToken on the Lumia chain side
    //   const rwaBalance = await rwaUSD.balanceOf(alice);
    //   expect(rwaBalance).to.be.eq(amount);
    //
    //   await rwaUSD.connect(alice).approve(realAssets, rwaBalance);
    //   await expect(realAssets.connect(alice).handleRwaRedeem(superformStrategy, alice, alice, rwaBalance))
    //     .to.changeTokenBalances(testUSDC,
    //       [alice, erc4626Vault], [amount, -amount]);
    //
    //   expect(await rwaUSD.balanceOf(alice)).to.be.eq(0);
    // });

    // TODO: when redeem and lumia shares are implemented
    // it("revenue from superform strategy", async function () {
    //   const { hyperStaking, superVault, superformStrategy, superform, erc4626Vault, testUSDC, signers } = await loadFixture(deployHyperStaking);
    //   const { deposit, allocation, rwaUSD, realAssets } = hyperStaking;
    //   const { vaultManager, alice } = signers;
    //
    //   // needed for simulate yield generation
    //   const tokenizedStrategy = await ethers.getContractAt("ITokenizedStrategy", superVault.target);
    //
    //   const amount = parseUnits("100", 6);
    //
    //   await testUSDC.connect(alice).approve(deposit, amount);
    //   await deposit.connect(alice).stakeDeposit(superformStrategy, alice, amount);
    //
    //   // lpToken on the Lumia chain side
    //   const rwaBalance = await rwaUSD.balanceOf(alice);
    //   expect(rwaBalance).to.be.eq(amount);
    //
    //   // change the ratio of the vault, increase the revenue
    //   const currentVaultAssets = await superform.getTotalAssets();
    //   await testUSDC.approve(tokenizedStrategy, currentVaultAssets); // double the assets
    //   await tokenizedStrategy.simulateYieldGeneration(erc4626Vault, currentVaultAssets);
    //
    //   const precisionError = 1n;
    //
    //   await rwaUSD.connect(alice).approve(realAssets, rwaBalance);
    //   await expect(realAssets.connect(alice).handleRwaRedeem(superformStrategy, alice, alice, rwaBalance))
    //     .to.changeTokenBalances(testUSDC,
    //       [alice, erc4626Vault], [amount - precisionError, -amount + precisionError]);
    //
    //   // everything has been withdrawn, and vault has double the assets,
    //   // so the revenue is the same as the amount
    //   const expectedRevenue = amount;
    //   expect(await allocation.checkRevenue(superformStrategy)).to.be.eq(expectedRevenue);
    //
    //   const revenueTx = allocation.connect(vaultManager).collectRevenue(superformStrategy, vaultManager, expectedRevenue);
    //
    //   // events
    //   await expect(revenueTx).to.emit(allocation, "Leave").withArgs(superformStrategy, vaultManager, expectedRevenue, anyValue);
    //   await expect(revenueTx).to.emit(allocation, "RevenueCollected").withArgs(superformStrategy, vaultManager, expectedRevenue);
    //
    //   // balance
    //   await expect(revenueTx).to.changeTokenBalances(testUSDC, [vaultManager, erc4626Vault], [expectedRevenue, -expectedRevenue]);
    //
    //   expect(await rwaUSD.balanceOf(alice)).to.be.eq(0);
    // });

    // TODO: when redeem and lumia shares are implemented
    // it("revenue should also depend on bridge safety margin", async function () {
    //   const { hyperStaking, superformStrategy, superVault, testUSDC, erc4626Vault, signers } = await loadFixture(deployHyperStaking);
    //   const { deposit, allocation, rwaUSD, realAssets } = hyperStaking;
    //   const { alice, vaultManager } = signers;
    //
    //   // needed for simulate yield generation
    //   const tokenizedStrategy = await ethers.getContractAt("ITokenizedStrategy", superVault.target);
    //
    //   const amount = parseUnits("50", 6);
    //
    //   await testUSDC.approve(deposit, amount);
    //   await deposit.stakeDeposit(superformStrategy, alice, amount);
    //
    //   // increase the revenue
    //   const additionlAssets = parseUnits("100", 6);
    //   await testUSDC.approve(superVault, additionlAssets);
    //   await tokenizedStrategy.simulateYieldGeneration(erc4626Vault, additionlAssets);
    //
    //   // withdraw half of the assets
    //   await rwaUSD.connect(alice).approve(realAssets, amount / 2n);
    //   await realAssets.connect(alice).handleRwaRedeem(superformStrategy, alice, alice, amount / 2n);
    //
    //   const newBridgeSafetyMargin = parseEther("0.1"); // 10%;
    //   const expectedRevenue = await allocation.checkRevenue(superformStrategy);
    //
    //   // only vault manager should be able to change the bridge safety margin
    //   await expect(allocation.setBridgeSafetyMargin(superformStrategy, newBridgeSafetyMargin))
    //     .to.be.reverted;
    //
    //   // must be grerated than min safety margin
    //   await expect(allocation.connect(vaultManager).setBridgeSafetyMargin(superformStrategy, 0))
    //     .to.be.revertedWithCustomError(allocation, "SafetyMarginTooLow");
    //
    //   // OK
    //   await allocation.connect(vaultManager).setBridgeSafetyMargin(superformStrategy, newBridgeSafetyMargin);
    //
    //   // the revenue should be less than before
    //   expect(await allocation.checkRevenue(superformStrategy)).to.be.lt(expectedRevenue);
    // });
  });
});
