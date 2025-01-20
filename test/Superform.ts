import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers, ignition, network } from "hardhat";
import { Signer, Contract, parseEther, parseUnits, ZeroAddress } from "ethers";

import SuperformMockModule from "../ignition/modules/test/SuperformMock";
import SuperformStrategyModule from "../ignition/modules/SuperformStrategy";

import * as shared from "./shared";
import { SingleDirectSingleVaultStateReqStruct } from "../typechain-types/contracts/external/superform/core/BaseRouter";

describe("Superform", function () {
  async function getMockedSuperform() {
    const [superManager, alice] = await ethers.getSigners();
    const testUSDC = await shared.deloyTestERC20("Test USD Coin", "tUSDC", 6);
    const erc4626Vault = await shared.deloyTestERC4626Vault(testUSDC);

    await testUSDC.mint(alice.address, parseUnits("1000000", 6));

    const { superformFactory, superformRouter, superVault, superPositions } = await ignition.deploy(SuperformMockModule, {
      parameters: {
        SuperformMockModule: {
          erc4626VaultAddress: await erc4626Vault.getAddress(),
        },
      },
    });

    const superformId = await superVault.superformIds(0);

    const [superformAddress,,] = await superformFactory.getSuperform(superformId);
    const superform = await ethers.getContractAt("BaseForm", superformAddress);

    // -------

    return {
      superformFactory, superformRouter, superVault, superPositions, superformId, superform, superManager, testUSDC, erc4626Vault, alice,
    };
  }

  const registerAERC20 = async (
    superformRouter: Contract,
    superformId: bigint,
    superform: Contract,
    superPositions: Contract,
    testUSDC: Contract,
  ) => {
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
  };

  async function deployHyperStaking() {
    const [owner, stakingManager, strategyVaultManager, bob, alice] = await ethers.getSigners();

    // --------------------- Deploy Tokens ----------------------

    const testUSDC = await shared.deloyTestERC20("Test USDC", "tUSDC", 6); // 6 decimal places
    const erc4626Vault = await shared.deloyTestERC4626Vault(testUSDC);

    // --------------------- Hyperstaking Diamond --------------------

    const {
      diamond, staking, factory, tier1, tier2, interchainFactory, superVault, superformIntegration,
    } = await shared.deployTestHyperStaking(0n, erc4626Vault);

    // ------------------ Create Staking Pools ------------------

    const usdcPoolId = await shared.createStakingPool(staking, testUSDC);

    // -------------------- Apply Strategies --------------------

    const defaultRevenueFee = parseEther("0"); // 0% fee
    const superformId = await superVault.superformIds(0);

    const { superformStrategy } = await ignition.deploy(SuperformStrategyModule, {
      parameters: {
        SuperformStrategyModule: {
          diamond: await diamond.getAddress(),
          stakeToken: await testUSDC.getAddress(),
          superformId,
        },
      },
    });

    // -------

    const superformFactory = await ethers.getContractAt("SuperformFactory", await superformIntegration.superformFactory());
    const superformRouter = await ethers.getContractAt("SuperformRouter", await superformIntegration.superformRouter());
    const superPositions = await ethers.getContractAt("SuperPositions", await superformIntegration.superPositions());

    const [superformAddress,,] = await superformFactory.getSuperform(superformId);
    const superform = await ethers.getContractAt("BaseForm", superformAddress);

    await registerAERC20(superformRouter, superformId, superform, superPositions, testUSDC);

    // -------

    await factory.connect(strategyVaultManager).addStrategy(
      usdcPoolId,
      superformStrategy,
      defaultRevenueFee,
    );

    // -------------------------------------------

    /* eslint-disable object-property-newline */
    return {
      diamond, // diamond
      staking, factory, tier1, tier2, superformIntegration, // diamond facets
      testUSDC, superformStrategy, // test contracts
      interchainFactory, // lumia
      usdcPoolId, superformId, // ids
      defaultRevenueFee, // values
      owner, stakingManager, strategyVaultManager, alice, bob, // addresses
    };
    /* eslint-enable object-property-newline */
  }

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
      const { superformFactory, superVault, superPositions, testUSDC, erc4626Vault } = await loadFixture(getMockedSuperform);
      const [, alice] = await ethers.getSigners();

      const superformId = await superVault.superformIds(0);
      expect(await superformFactory.isSuperform(superformId)).to.equal(true);
      expect(await superformFactory.vaultToSuperforms(erc4626Vault.target, 0)).to.equal(superformId);

      expect(await superPositions.name()).to.equal("Super Test Positions");
      expect(await superPositions.symbol()).to.equal("STP");
      expect(await superPositions.dynamicURI()).to.equal("dynamicURI");

      const [superformAddress, formId, chainId] = await superformFactory.getSuperform(superformId);

      expect(formId).to.equal(3);
      expect(chainId).to.equal(network.config.chainId);

      const superform = await ethers.getContractAt("ERC4626Form", superformAddress);

      expect(await superform.getVaultName()).to.equal(await erc4626Vault.name());
      expect(await superform.getVaultSymbol()).to.equal(await erc4626Vault.symbol());

      expect(await superform.vault()).to.equal(erc4626Vault.target);
      expect(await superform.asset()).to.equal(testUSDC.target);

      expect(await superPositions.balanceOf(alice.address, superformId)).to.equal(0);
      expect(await superPositions.totalSupply(superformId)).to.equal(0);
    });

    it("It should be possible to deposit USDC using superRouter", async function () {
      const { superform, superformId, superPositions, alice } = await loadFixture(getMockedSuperform);

      // deposit amount
      const amount = parseUnits("100", 6);

      const maxSlippage = 100n; // 1%
      const outputAmount = await superform.previewDepositTo(amount);

      await superUSDCDeposit(amount, alice, outputAmount, maxSlippage);

      const outputAmountSlipped = outputAmount * (10000n - maxSlippage) / 10000n;
      expect(await superPositions.balanceOf(alice.address, superformId)).to.be.gt(outputAmountSlipped);
    });

    it("It should be possible to transmute superPositions to aERC20", async function () {
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

    it("It should be possible to withdraw superPositions", async function () {
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
    it.only("Superform strategy with vault should be created along with LP token on lumia side", async function () {
      const { diamond, factory, tier2, superformStrategy, interchainFactory, testUSDC, usdcPoolId, superformId } = await deployHyperStaking();

      expect(await superformStrategy.DIAMOND()).to.equal(diamond);
      expect(await superformStrategy.SUPERFORM_ID()).to.equal(superformId);
      expect(await superformStrategy.STAKE_TOKEN()).to.equal(testUSDC);

      const revenueAsset = await superformStrategy.revenueAsset(); // aERC20 from superpositons
      expect(revenueAsset).to.not.equal(ZeroAddress);

      // VaultInfo
      expect((await factory.vaultInfo(superformStrategy)).strategy).to.equal(superformStrategy);
      expect((await factory.vaultInfo(superformStrategy)).poolId).to.equal(usdcPoolId);
      expect((await factory.vaultInfo(superformStrategy)).asset).to.equal(revenueAsset);

      const [vaultToken] = await tier2.vaultTier2Info(superformStrategy);
      expect(vaultToken).to.not.equal(ZeroAddress);

      expect(await interchainFactory.getLpToken(vaultToken)).to.not.equal(ZeroAddress);
    });
  });
});
