import * as shared from "./shared";
import { ignition } from "hardhat";
import { parseEther, parseUnits, Contract } from "ethers";

import { time } from "@nomicfoundation/hardhat-toolbox/network-helpers";

import HyperStakingModule from "../ignition/modules/HyperStaking";
import LumiaDiamondModule from "../ignition/modules/LumiaDiamond";
import OneChainMailboxModule from "../ignition/modules/test/OneChainMailbox";
import CurveMockModule from "../ignition/modules/test/CurveMock";
import InvariantCheckerModule from "../ignition/modules/test/InvariantChecker";

declare global {
  /* eslint-disable no-var */
  var $invChecker: Contract | undefined;
  var setInvChecker: (c: Contract) => void;
  var clearInvChecker: () => void;
  /* eslint-enable no-var */
}

globalThis.$invChecker = undefined;

globalThis.setInvChecker = (c: Contract) => {
  globalThis.$invChecker = c;
};

globalThis.clearInvChecker = () => {
  globalThis.$invChecker = undefined;
};

// Hardhat fixture shared across tests, deploy core contracts once
export async function deployHyperStakingBase() {
  const signers = await shared.getSigners();

  // --------------------- Deploy Tokens -------------------

  const stableUnits = (val: string) => parseUnits(val, 6);

  const testERC20 = await shared.deployTestERC20("Test ERC20 Token", "tERC20");
  const testWstETH = await shared.deployTestERC20("Test Wrapped Liquid Staked ETH", "tWstETH");
  const testUSDC = await shared.deployTestERC20("Test USDC", "tUSDC", 6);
  const testUSDT = await shared.deployTestERC20("Test USDT", "tUSDT", 6);

  const erc4626Vault = await shared.deployTestERC4626Vault(testUSDC);

  await testERC20.mint(signers.alice, parseEther("1000"));
  await testERC20.mint(signers.bob, parseEther("1000"));

  await testUSDC.mint(signers.alice, stableUnits("1000000"));
  await testUSDC.mint(signers.bob, stableUnits("1000000"));

  await testUSDT.mint(signers.alice, stableUnits("1000000"));
  await testUSDT.mint(signers.bob, stableUnits("1000000"));

  // -------------------- Hyperlane --------------------

  // the same for both sides of the test "oneChain" bridge
  const testDestination = 31337;
  const defaultMailboxFee = 0n;

  const { mailbox } = await ignition.deploy(OneChainMailboxModule, {
    parameters: {
      OneChainMailboxModule: {
        fee: defaultMailboxFee,
        localDomain: testDestination,
      },
    },
  });
  const mailboxAddress = await mailbox.getAddress();

  // -------------------- Superform --------------------

  const {
    superformFactory, superformRouter, superVault, superPositions,
  } = await shared.deploySuperformMock(erc4626Vault);

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

  // -------------------- Hyperstaking ---------------------

  const defaultWithdrawDelay = 3 * 24 * 60 * 60; // 3 days

  const hyperStaking = await ignition.deploy(HyperStakingModule, {
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

  // -------------------- Lumia Diamond --------------------

  const lumiaDiamond = await ignition.deploy(LumiaDiamondModule, {
    parameters: {
      LumiaDiamondModule: {
        lumiaMailbox: mailboxAddress,
      },
    },
  });

  // -------------------- Invariant Checker --------------------

  const { invariantChecker } = await ignition.deploy(InvariantCheckerModule, {
    parameters: {
      InvariantCheckerModule: {
        allocationFacet: await hyperStaking.allocation.getAddress(),
        lockboxFacet: await hyperStaking.lockbox.getAddress(),
        hyperlaneHandlerFacet: await lumiaDiamond.hyperlaneHandler.getAddress(),
      },
    },
  });

  // -------------------- Other/Configuration --------------------

  // finish setup for hyperstaking
  await hyperStaking.lockbox.connect(signers.vaultManager).proposeLumiaFactory(
    lumiaDiamond.hyperlaneHandler,
  );
  await time.setNextBlockTimestamp(await shared.getCurrentBlockTimestamp() + 3600 * 24); // 1 day later
  await hyperStaking.lockbox.connect(signers.vaultManager).applyLumiaFactory();

  // finish setup for lumia diamond
  const authorized = true;
  await lumiaDiamond.hyperlaneHandler.connect(signers.lumiaFactoryManager).updateAuthorizedOrigin(
    hyperStaking.lockbox,
    authorized,
    testDestination,
  );

  /* eslint-disable object-property-newline */
  return {
    signers, // signers
    hyperStaking, lumiaDiamond, // diamonds deployment
    defaultWithdrawDelay, // deposit parameter
    testERC20, testWstETH, testUSDC, testUSDT, erc4626Vault, // test tokens
    superVault, superformFactory, // superform mock
    curvePool, curveRouter, // curve mock
    mailbox, // hyperlane test mailbox
    invariantChecker, // invariant checker
  };
  /* eslint-enable object-property-newline */
}
