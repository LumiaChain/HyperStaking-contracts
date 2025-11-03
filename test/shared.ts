import { expect } from "chai";
import { ignition, ethers, network } from "hardhat";
import { Contract, ZeroAddress, ZeroBytes32, parseEther, parseUnits, Addressable, TransactionResponse, Log } from "ethers";
import { time } from "@nomicfoundation/hardhat-toolbox/network-helpers";

import HyperStakingModule from "../ignition/modules/HyperStaking";
import LumiaDiamondModule from "../ignition/modules/LumiaDiamond";
import OneChainMailboxModule from "../ignition/modules/test/OneChainMailbox";
import SuperformMockModule from "../ignition/modules/test/SuperformMock";
import CurveMockModule from "../ignition/modules/test/CurveMock";

import TestERC20Module from "../ignition/modules/test/TestERC20";
import ReserveStrategyModule from "../ignition/modules/test/MockReserveStrategy";

import { CurrencyStruct } from "../typechain-types/contracts/hyperstaking/interfaces/IHyperFactory";

import { IERC20, ISuperformIntegration } from "../typechain-types";

import { SingleDirectSingleVaultStateReqStruct } from "../typechain-types/contracts/external/superform/core/BaseRouter";

// full - because there are two differnet vesions of IERC20 used in the project
export const fullyQualifiedIERC20 = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

// -------------------- Accounts --------------------

export async function getSigners() {
  const [
    owner, stakingManager, vaultManager, strategyManager, lumiaFactoryManager, bob, alice,
  ] = await ethers.getSigners();

  const strategyUpgrader = owner;

  return { owner, stakingManager, vaultManager, strategyManager, strategyUpgrader, lumiaFactoryManager, bob, alice };
}

// -------------------- Currency --------------------

export const nativeTokenAddress = ZeroAddress;

export function nativeCurrency(): CurrencyStruct {
  return { token: nativeTokenAddress };
}

/// token contract address
export function erc20Currency(token: string): CurrencyStruct {
  return { token };
}

// -------------------- Deployment Helpers --------------------

export async function deploySuperformMock(erc4626Vault: Contract) {
  const testUSDC = await ethers.getContractAt(fullyQualifiedIERC20, await erc4626Vault.asset());

  // --- set TokenizedStrategy code on a given address ---

  const factory = await ethers.getContractFactory("TokenizedStrategy");
  const instance = await factory.deploy(testUSDC);

  const deployedBytecode = await ethers.provider.getCode(await instance.getAddress());

  await network.provider.send("hardhat_setCode", [
    "0xBB51273D6c746910C7C06fe718f30c936170feD0",
    deployedBytecode,
  ]);

  // -------------------- Superform Mock --------------------

  return ignition.deploy(SuperformMockModule, {
    parameters: {
      SuperformMockModule: {
        erc4626VaultAddress: await erc4626Vault.getAddress(),
      },
    },
  });
}

export async function deployTestHyperStaking(mailboxFee: bigint) {
  const { alice, bob, vaultManager, lumiaFactoryManager } = await getSigners();
  const testDestination = 31337; // the same for both sides of the test "oneChain" bridge

  // -------------------- Deploy Tokens --------------------

  const testUSDC = await deployTestERC20("Test USDC", "tUSDC", 6);
  const testUSDT = await deployTestERC20("Test USDT", "tUSDT", 6);

  const stableUnits = (val: string) => parseUnits(val, 6);
  await testUSDC.mint(alice.address, stableUnits("1000000"));
  await testUSDC.mint(bob.address, stableUnits("1000000"));

  await testUSDT.mint(alice.address, stableUnits("1000000"));
  await testUSDT.mint(bob.address, stableUnits("1000000"));

  // -------------------- Hyperlane --------------------

  const { mailbox } = await ignition.deploy(OneChainMailboxModule, {
    parameters: {
      OneChainMailboxModule: {
        fee: mailboxFee,
        localDomain: testDestination,
      },
    },
  });
  const mailboxAddress = await mailbox.getAddress();

  // -------------------- Superform --------------------

  const erc4626Vault = await deployTestERC4626Vault(testUSDC);
  const {
    superformFactory, superformRouter, superVault, superPositions,
  } = await deploySuperformMock(erc4626Vault);

  // -------------------- Curve --------------------

  const { curvePool, curveRouter } = await ignition.deploy(CurveMockModule, {
    parameters: {
      CurveMockModule: {
        usdcAddress: await testUSDC.getAddress(),
        usdtAddress: await testUSDT.getAddress(),
      },
    },
  });

  // fill the pool with some USDC and USDT
  await testUSDC.transfer(await curvePool.getAddress(), stableUnits("500000"));
  await testUSDT.transfer(await curvePool.getAddress(), stableUnits("500000"));

  // -------------------- HyperStaking --------------------

  const { diamond, deposit, hyperFactory, allocation, lockbox, routeRegistry, stakeInfoRoute, superformIntegration, curveIntegration } = await ignition.deploy(HyperStakingModule, {
    parameters: {
      HyperStakingModule: {
        lockboxMailbox: mailboxAddress,
        lockboxDestination: testDestination,
        superformFactory: await superformFactory.getAddress(),
        superformRouter: await superformRouter.getAddress(),
        superPositions: await superPositions.getAddress(),
        curveRouter: await curveRouter.getAddress(),
      },
    },
  });

  const defaultWithdrawDelay = 3 * 24 * 60 * 60; // 3 days

  // -------------------- Lumia Diamond --------------------

  const { lumiaDiamond, hyperlaneHandler, realAssets, stakeRedeemRoute } = await ignition.deploy(LumiaDiamondModule, {
    parameters: {
      LumiaDiamondModule: {
        lumiaMailbox: mailboxAddress,
      },
    },
  });

  // -------------------- Other/Configuration --------------------

  // finish setup for hyperstaking
  await lockbox.connect(vaultManager).proposeLumiaFactory(hyperlaneHandler);
  await time.setNextBlockTimestamp(await getCurrentBlockTimestamp() + 3600 * 24); // 1 day later
  await lockbox.connect(vaultManager).applyLumiaFactory();

  // finish setup for lumia diamond
  const authorized = true;
  await hyperlaneHandler.connect(lumiaFactoryManager).updateAuthorizedOrigin(
    lockbox,
    authorized,
    testDestination,
  );

  /* eslint-disable object-property-newline */
  return {
    diamond,
    deposit, hyperFactory, allocation, lockbox, // hyperstaking facets
    defaultWithdrawDelay, // deposit parameter
    routeRegistry, stakeInfoRoute, // hyperstaking route facets
    superformIntegration, curveIntegration, // hyperstaking integration facets
    lumiaDiamond, hyperlaneHandler, realAssets, stakeRedeemRoute, // lumia diamond facets
    superVault, superformFactory, // superform mock
    curvePool, curveRouter, // curve mock
    testUSDC, testUSDT, erc4626Vault, // test tokens
    mailbox, // hyperlane test mailbox
  };
  /* eslint-enable object-property-newline */
}

export async function deployTestERC20(name: string, symbol: string, decimals: number = 18): Promise<Contract> {
  const { testERC20 } = await ignition.deploy(TestERC20Module, {
    parameters: {
      TestERC20Module: {
        name,
        symbol,
        decimals,
      },
    },
  });
  return testERC20;
}

export async function deployTestERC4626Vault(asset: Contract): Promise<Contract> {
  return ethers.deployContract("TestERC4626", [await asset.getAddress()]) as unknown as Promise<Contract>;
}

// -------------------- Strategies --------------------

/// ZeroAddress is used for native currency
export async function createReserveStrategy(
  diamond: Contract,
  stakeTokenAddress: string,
  assetAddress: string,
  assetPrice: bigint,
) {
  const { reserveStrategy } = await ignition.deploy(ReserveStrategyModule, {
    parameters: {
      ReserveStrategyModule: {
        diamond: await diamond.getAddress(),
        stake: stakeTokenAddress,
        asset: assetAddress,
        assetPrice,
      },
    },
  });

  const { owner, strategyManager } = await getSigners();

  const reserveStrategySupply = parseEther("50");

  const asset = (await ethers.getContractAt(fullyQualifiedIERC20, assetAddress)) as unknown as IERC20;

  await asset.transfer(strategyManager, reserveStrategySupply); // owner -> strategyManager
  await asset.connect(strategyManager).approve(reserveStrategy.target, reserveStrategySupply);

  await reserveStrategy.connect(strategyManager).supplyRevenueAsset(reserveStrategySupply);

  await owner.sendTransaction({
    to: reserveStrategy,
    value: reserveStrategySupply,
  });

  return reserveStrategy;
}

// -------------------- Superform AERC20 --------------------

export async function registerAERC20(
  superformIntegration: ISuperformIntegration,
  superVault: Contract,
  testUSDC: Contract,
): Promise<IERC20> {
  const superformFactory = await ethers.getContractAt("SuperformFactory", await superformIntegration.superformFactory());

  const superformId = await superformFactory.vaultToSuperforms(superVault, 0);
  const superformRouter = await ethers.getContractAt("SuperformRouter", await superformIntegration.superformRouter());
  const superPositions = await ethers.getContractAt("SuperPositions", await superformIntegration.superPositions());

  const [superformAddress,,] = await superformFactory.getSuperform(superformId);
  const superform = await ethers.getContractAt("BaseForm", superformAddress);

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

// -------------------- Gauntlet --------------------

export async function solveGauntletDepositRequest(
  tx: TransactionResponse,
  gauntletStrategy: Contract,
  provisioner: Contract,
  token: Addressable,
  amount: bigint,
  requestId: number,
) {
  const depositRequestHash = await getEventArg(
    tx,
    "AeraAsyncDepositHash",
    gauntletStrategy,
  );
  expect(depositRequestHash).to.not.equal(ZeroBytes32);

  const units = await gauntletStrategy.recordedAllocation(requestId);
  await provisioner.testSolveDeposit(
    token,
    await gauntletStrategy.getAddress(),
    amount,
    units,
    depositRequestHash,
  );
}

export async function solveGauntletRedeemRequest(
  tx: TransactionResponse,
  gauntletStrategy: Contract,
  provisioner: Contract,
  token: Addressable,
  amount: bigint,
  requestId: number,
) {
  const redeemRequestHash = await getEventArg(
    tx,
    "AeraAsyncRedeemHash",
    gauntletStrategy,
  );
  expect(redeemRequestHash).to.not.equal(ZeroBytes32);

  const units = await gauntletStrategy.recordedExit(requestId);
  await provisioner.testSolveRedeem(
    token,
    await gauntletStrategy.getAddress(),
    amount,
    units,
    redeemRequestHash,
  );
}

// -------------------- Other Helpers --------------------

export async function getLastClaimId(deposit: Contract, reserveStrategy1: Addressable, owner: Addressable) {
  const lastClaims = await deposit.lastClaims(reserveStrategy1, owner, 1);
  return lastClaims[0] as bigint; // return only the claimId
}

export async function getRevenueAsset(strategy: Contract) {
  const revenueAssetAddress = await strategy.revenueAsset();
  return ethers.getContractAt(
    "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
    revenueAssetAddress,
  );
}

export async function getDerivedTokens(hyperlaneHandler: Contract, strategy: string) {
  const principalTokenAddress = (await hyperlaneHandler.getRouteInfo(strategy)).assetToken;
  const principalToken = await ethers.getContractAt("LumiaPrincipal", principalTokenAddress);

  const vaultSharesAddress = (await hyperlaneHandler.getRouteInfo(strategy)).vaultShares;
  const vaultShares = await ethers.getContractAt("LumiaVaultShares", vaultSharesAddress);

  return { principalToken, vaultShares };
}

export async function getCurrentBlockTimestamp() {
  const blockNumber = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blockNumber);
  return block!.timestamp;
}

export async function getEventArg(tx: TransactionResponse, eventName: string, contract: Contract) {
  const receipt = await tx.wait();
  const logs = receipt!.logs;
  const parsedEvent = logs.map((rawLog: Log) => {
    try {
      return contract.interface.parseLog(rawLog);
    } catch {
      return null;
    }
  }).find((parsedLog: Log) => parsedLog !== null && parsedLog.name === eventName);

  if (parsedEvent && parsedEvent.args) {
    // NOTE: return only the first argument of the event
    return parsedEvent.args[0];
  }
  return null;
}
