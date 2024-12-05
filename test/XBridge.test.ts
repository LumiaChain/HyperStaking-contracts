import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ignition, ethers } from "hardhat";

import OneChainMailboxModule from "../ignition/modules/OneChainMailbox";
import LumiaXERC20LockboxModule from "../ignition/modules/LumiaXERC20Lockbox";
import LumiaReceiverModule from "../ignition/modules/LumiaReceiver";

import * as shared from "./shared";

import { Contract, parseEther } from "ethers";

describe("XBridge", function () {
  type ChainADeployment = {
    mailbox: Contract;
    erc20: Contract;
    xerc20: Contract;
    lockbox: Contract;
  };

  type ChainBDeployment = {
    mailbox: Contract;
    xerc20: Contract;
    lumiaReceiver: Contract;
  };

  async function deployXBridge() {
    const tokenName = "Test Token";
    const tokenSymbol = "TT";

    const [owner, broker] = await ethers.getSigners();

    // --------------------- Deploy

    const { mailbox } = await ignition.deploy(OneChainMailboxModule);
    const mailboxAddress = await mailbox.getAddress();

    const erc20 = await shared.deloyTestERC20(tokenName, tokenSymbol);
    const xerc20A = await shared.deloyTestXERC20(mailboxAddress, tokenName, tokenSymbol);
    const xerc20B = await shared.deloyTestXERC20(mailboxAddress, tokenName, tokenSymbol);

    const lockbox = (await ignition.deploy(LumiaXERC20LockboxModule, {
      parameters: {
        LumiaXERC20LockboxModule: {
          mailbox: mailboxAddress,
          destination: 31337,
          recipient: await xerc20B.getAddress(),
          xerc20Address: await xerc20A.getAddress(),
          erc20Address: await erc20.getAddress(),
        },
      },
    })).xERC20Lockbox;

    const { lumiaReceiver } = await ignition.deploy(LumiaReceiverModule);

    const chainA: ChainADeployment = {
      mailbox,
      erc20,
      xerc20: xerc20A,
      lockbox,
    };

    const chainB: ChainBDeployment = {
      mailbox,
      xerc20: xerc20B,
      lumiaReceiver,
    };

    // --------------------- Setup

    // chainA
    await xerc20A.setLockbox(lockbox);

    // chainB
    const mintingLimit = parseEther("1000000");
    const burningLimit = parseEther("1000000");

    // await xerc20B.setLimits(mailbox, mintingLimit, burningLimit);
    await xerc20B.setLimits(lumiaReceiver, mintingLimit, burningLimit);
    await xerc20B.setOriginLockbox(lockbox);
    await xerc20B.setLumiaReceiver(lumiaReceiver);
    await lumiaReceiver.updateRegisteredToken(xerc20B, true);
    await lumiaReceiver.setBroker(broker);

    // ---------------------

    return { chainA, chainB, owner, broker, mintingLimit };
  }

  describe("Scenarios", function () {
    it("broker should be able to emit tokens", async function () {
      const { chainB, owner, broker, mintingLimit } = await loadFixture(deployXBridge);
      const { xerc20, lumiaReceiver } = chainB;

      const amount = parseEther("1000");

      await expect(lumiaReceiver.emitTokens(xerc20, amount))
        .to.be.revertedWithCustomError(lumiaReceiver, "UnauthorizedBroker")
        .withArgs(owner.address);

      await expect(lumiaReceiver.connect(broker).emitTokens(xerc20, amount))
        .to.changeTokenBalances(xerc20, [broker], [amount]);

      expect(await lumiaReceiver.waitings(xerc20)).to.eq(amount);

      await expect(lumiaReceiver.connect(broker).emitTokens(xerc20, mintingLimit))
        .to.revertedWithCustomError(xerc20, "IXERC20_NotHighEnoughLimits");
    });

    it("return token should pass message through mailbox and resolve waitings", async function () {
      const { chainA, chainB, broker } = await loadFixture(deployXBridge);

      const amount = parseEther("1000");

      await chainB.lumiaReceiver.connect(broker).emitTokens(chainB.xerc20, amount);

      const dispatchFee = await chainA.lockbox.quoteDispatch(amount);

      await chainA.erc20.approve(chainA.lockbox, amount);
      await chainA.lockbox.returnToken(amount, { value: dispatchFee });

      // waiting should be resolved
      expect(await chainB.lumiaReceiver.waitings(chainB.xerc20)).to.eq(0);
    });
  });
});
