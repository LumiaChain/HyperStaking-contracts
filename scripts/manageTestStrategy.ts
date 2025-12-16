import { ethers } from "hardhat";
import { parseUnits, parseEther, formatEther } from "ethers";
import { sendEther, processTx } from "./libraries/utils";
import * as shared from "../test/shared";

import { RouteRegistryDataStruct } from "../typechain-types/contracts/hyperstaking/interfaces/IRouteRegistry";
import { StakeInfoDataStruct } from "../typechain-types/contracts/hyperstaking/interfaces/IStakeInfoRoute";
import { StakeRewardDataStruct } from "../typechain-types/contracts/hyperstaking/interfaces/IStakeRewardRoute";
import { StakeRedeemDataStruct } from "../typechain-types/contracts/lumia-diamond//interfaces/IStakeRedeemRoute";

import * as sepoliaAddresses from "../ignition/parameters.sepolia.json";
import * as beamAddresses from "../ignition/parameters.lumia_beam.json";

const SEPOLIA_CHAIN_ID = 11155111;

// --- Get Contracts ---

async function getContracts() {
  const signers = await shared.getSigners();

  const testStrategy = await ethers.getContractAt(
    "MockReserveStrategy",
    sepoliaAddresses.General.testReserveStrategy,
  );

  const ethYieldToken = await ethers.getContractAt(
    "TestERC20",
    sepoliaAddresses.General.testEthYieldToken,
  );

  const diamond = sepoliaAddresses.General.diamond;

  // diamond hyper factory facet
  const hyperFactory = await ethers.getContractAt(
    "IHyperFactory",
    diamond,
  );

  // diamond deposit facet
  const deposit = await ethers.getContractAt(
    "IDeposit",
    diamond,
  );

  const allocation = await ethers.getContractAt(
    "IAllocation",
    diamond,
  );

  const routeRegistry = await ethers.getContractAt(
    "IRouteRegistry",
    diamond,
  );

  const stakeInfoRoute = await ethers.getContractAt(
    "IStakeInfoRoute",
    diamond,
  );

  const stakeRewardRoute = await ethers.getContractAt(
    "IStakeRewardRoute",
    diamond,
  );

  // diamond lockbox facet
  const lockbox = await ethers.getContractAt(
    "ILockbox",
    diamond,
  );

  return {
    diamond,
    signers,
    testStrategy,
    ethYieldToken,
    hyperFactory,
    deposit,
    allocation,
    routeRegistry,
    stakeInfoRoute,
    stakeRewardRoute,
    lockbox,
  };
}

async function getBeamContracts() {
  const signers = await shared.getSigners();

  const lumiaDiamond = beamAddresses.General.lumiaDiamond;
  const testStrategyAddress = sepoliaAddresses.General.testReserveStrategy;

  // lumia diamond hyperlane handler facet
  const hyperlaneHandler = await ethers.getContractAt(
    "IHyperlaneHandler",
    lumiaDiamond,
  );

  const realAssets = await ethers.getContractAt(
    "IRealAssets",
    beamAddresses.General.lumiaDiamond,
  );

  const stakeRedeemRoute = await ethers.getContractAt(
    "IStakeRedeemRoute",
    lumiaDiamond,
  );

  return {
    signers,
    testStrategyAddress,
    lumiaDiamond,
    hyperlaneHandler,
    realAssets,
    stakeRedeemRoute,
  };
}

// --- Commands ---

async function cmdAddStrategy() {
  const { signers, routeRegistry, hyperFactory, testStrategy } = await getContracts();
  const { vaultManager } = signers;

  console.log(`Adding reserve strategy ${testStrategy.target} via hyperFactory...`);

  const name = "Test Native Strategy";
  const symbol = "tETH1";

  const quoteVaule = await routeRegistry.quoteDispatchRouteRegistry({
    strategy: testStrategy,
    name,
    symbol,
    decimals: 18,
    metadata: "0x",
  } as RouteRegistryDataStruct);

  console.log("Quoted value for adding strategy:", formatEther(quoteVaule));

  const tx = await hyperFactory.connect(vaultManager).addStrategy(
    testStrategy,
    name,
    symbol,
    { value: quoteVaule },
  );

  await processTx(tx, "Add Strategy");
}

async function cmdSetStrategyAssetPrice() {
  const { signers, testStrategy } = await getContracts();
  const { strategyManager } = signers;

  const newPrice = parseEther("1.2"); // new price in ETH +20% from 1 ETH

  console.log(
    `Setting new asset price for strategy ${testStrategy.target} to ${formatEther(newPrice)}...`,
  );

  const tx = await testStrategy.connect(strategyManager).setAssetPrice(newPrice);
  await processTx(tx, "Set Strategy Asset Price");
}

async function cmdSupplyStrategy() {
  const amountRaw = 1000; // amount of yield tokens (without decimals);
  const decimals = 18;

  if (!amountRaw) {
    throw new Error("Usage: supply-strategy <amountEth>");
  }

  const amount = parseUnits(amountRaw.toString(), decimals);

  const { signers, testStrategy, ethYieldToken } = await getContracts();
  const { owner, strategyManager } = signers;

  console.log(
    `Supplying ${amountRaw} of asset ${ethYieldToken.target} to testStrategy...`,
  );

  let tx;

  // mint yield tokens to strategyManager
  tx = await ethYieldToken.connect(owner).mint(strategyManager.address, amount);
  await processTx(tx, "Mint yield tokens to strategyManager");

  tx = await ethYieldToken.connect(strategyManager).approve(
    testStrategy.target,
    amount,
  );
  await processTx(tx, "Approve yield tokens to testStrategy");

  tx = await testStrategy
    .connect(strategyManager)
    .supplyRevenueAsset(amount);
  await processTx(tx, "Supply revenue asset to testStrategy");
}

async function cmdSetupLockbox() {
  const { signers, lockbox } = await getContracts();
  const { vaultManager } = signers;

  const newDestination = 2030232745;
  const newLumiaFactory = "0x6EF866091F2cee3A58279AF877C2266498c95D31";

  console.log("Setting up lockbox...");
  console.log("New destination:", newDestination);

  let tx;
  tx = await lockbox.connect(vaultManager).setDestination(newDestination);
  await processTx(tx, "Set Lockbox Destination");

  tx = await lockbox.connect(vaultManager).proposeLumiaFactory(newLumiaFactory);
  await processTx(tx, "Propose Lumia Factory");

  tx = await lockbox.connect(vaultManager).applyLumiaFactory();
  await processTx(tx, "Apply Lumia Factory");

  console.log("Lockbox setup complete.");
}

async function cmdSetLockboxISM() {
  const { signers, lockbox } = await getContracts();
  const { vaultManager } = signers;

  const newISM = "0x5eabFcdDf2e8816CA5E466921c865633C277A7a9";
  console.log("Setting new Lockbox ISM:", newISM);

  const tx = await lockbox.connect(vaultManager).setInterchainSecurityModule(newISM);
  await processTx(tx, "Set Lockbox ISM");
}

// set both fee and recipient
async function cmdSetFeeData() {
  const { signers, allocation, testStrategy } = await getContracts();
  const { bob, vaultManager } = signers;

  const newFeeRate = parseEther("0.02"); // 2%
  const newFeeRecipient = bob.address;

  console.log(
    `Setting new fee data for strategy ${testStrategy.target}: rate=${formatEther(newFeeRate)}, recipient=${newFeeRecipient}...`,
  );

  await processTx(
    await allocation.connect(vaultManager).setFeeRecipient(
      testStrategy,
      newFeeRecipient,
    ),
    "Set Fee Recipient",
  );

  await processTx(
    await allocation.connect(vaultManager).setFeeRate(
      testStrategy,
      newFeeRate,
    ),
    "Set Fee Rate",
  );
}

async function cmdSetupHyperlaneHandler() {
  const { signers, hyperlaneHandler } = await getBeamContracts();
  const { lumiaFactoryManager } = signers;

  const originLockbox = sepoliaAddresses.General.diamond;

  const tx = await hyperlaneHandler
    .connect(lumiaFactoryManager)
    .updateAuthorizedOrigin(
      originLockbox,
      true,
      SEPOLIA_CHAIN_ID,
    );
  await processTx(tx, "Authorize Origin Lockbox");
}

async function cmdSetLumiaMailbox() {
  const { signers, hyperlaneHandler } = await getBeamContracts();
  const { lumiaFactoryManager } = signers;

  const mailbox = beamAddresses.General.lumiaMailbox;

  const tx = await hyperlaneHandler
    .connect(lumiaFactoryManager)
    .setMailbox(mailbox);
  await processTx(tx, "Set Lumia Mailbox");
}

// --- Main Operations Commands ---

async function cmdReportRevenue() {
  const { signers, testStrategy, allocation, stakeRewardRoute } = await getContracts();
  const { vaultManager } = signers;

  console.log(`Reporting revenue for strategy ${testStrategy.target}...`);

  // TODO quoteReport

  const stakeAdded = await allocation.checkRevenue(testStrategy);
  console.log(stakeAdded);
  console.log("Stake added from revenue:", formatEther(stakeAdded));

  const dispatchFee = await stakeRewardRoute.quoteDispatchStakeReward({
    strategy: testStrategy,
    stakeAdded,
  } as StakeRewardDataStruct);

  console.log("Dispatch fee for reporting revenue:", formatEther(dispatchFee));

  const tx = await allocation.connect(vaultManager).report(
    testStrategy,
    { value: dispatchFee },
  );
  await processTx(tx, "Report Strategy Revenue");
}

async function cmdStakeDeposit() {
  const { signers, deposit, stakeInfoRoute, testStrategy } = await getContracts();
  const { alice } = signers;

  const stakeAmount = parseEther("0.1");
  console.log(`Staking deposit of ${formatEther(stakeAmount)} ETH for strategy ${testStrategy.target}...`);

  const dispatchFee = await stakeInfoRoute.quoteDispatchStakeInfo({
    strategy: testStrategy,
    sender: alice.address,
    stake: stakeAmount,
  } as StakeInfoDataStruct);

  console.log("Dispatch fee for staking deposit:", formatEther(dispatchFee));

  const tx = await deposit.connect(alice).stakeDeposit(
    testStrategy,
    alice,
    stakeAmount,
    { value: stakeAmount + dispatchFee },
  );
  await processTx(tx, "Stake Deposit");
}

async function cmdSharesRedeem() {
  const { signers, realAssets, hyperlaneHandler, stakeRedeemRoute, testStrategyAddress } = await getBeamContracts();
  const { alice } = signers;

  const sharesAmount = parseEther("0.2");
  console.log(`Redeeming ${formatEther(sharesAmount)} shares for strategy ${testStrategyAddress}...`);

  const routeInfo = await hyperlaneHandler.getRouteInfo(testStrategyAddress);
  const shares = await ethers.getContractAt(
    "LumiaVaultShares", routeInfo.vaultShares,
  );

  await processTx(
    await shares.connect(alice).approve(
      realAssets.target,
      sharesAmount,
    ),
    "Approve Shares to RealAssets",
  );

  const dispatchFee = await stakeRedeemRoute.quoteDispatchStakeRedeem({
    strategy: testStrategyAddress,
    sender: alice.address,
    redeemAmount: sharesAmount,
  } as StakeRedeemDataStruct);

  await processTx(
    await realAssets.connect(alice).redeem(
      testStrategyAddress,
      alice,
      alice,
      sharesAmount,
      { value: dispatchFee },
    ),
    "Redeem Shares",
  );
}

async function cmdReexecuteFailedRedeem() {
  const { signers, lockbox } = await getContracts();
  const { alice } = signers;

  console.log(`Reexecuting failed redeem messages for ${alice.address}...`);

  const failedRedeemId = 0;
  const tx = await lockbox.connect(alice).reexecuteFailedRedeem(failedRedeemId);
  await processTx(tx, "Reexecute Failed Redeem Messages");
}

async function cmdClaimWithdraw() {
  const { signers, deposit, testStrategy } = await getContracts();
  const { alice } = signers;

  console.log(`Claiming withdraw for user ${alice.address} on strategy ${testStrategy.target}...`);

  const ids = [4];

  const tx = await deposit.connect(alice).claimWithdraws(ids, alice);
  await processTx(tx, "Claim Withdraw");
}

// --- Info Command ---

async function cmdInfo() {
  const {
    diamond, signers, testStrategy, ethYieldToken, deposit, allocation, hyperFactory, lockbox,
  } = await getContracts();

  const { owner, strategyManager, vaultManager, alice } = signers;

  // native ETH balances
  const strategyEthBalance = await ethers.provider.getBalance(testStrategy);
  const diamondEthBalance = await ethers.provider.getBalance(diamond);
  const ownerEthBalance = await ethers.provider.getBalance(owner);
  const aliceEthBalance = await ethers.provider.getBalance(alice);
  const vaultManagerEthBalance = await ethers.provider.getBalance(vaultManager);

  // yield token balances
  const strategyBalance = await ethYieldToken.balanceOf(testStrategy);
  const diamondBalance = await ethYieldToken.balanceOf(diamond);

  console.log("=== Info ===");
  console.log("testStrategy:", await testStrategy.getAddress());
  console.log("depositFacet (diamond):", await deposit.getAddress());
  console.log("ethYieldToken:", await ethYieldToken.getAddress());

  console.log("owner:", owner.address);
  console.log("strategyManager:", strategyManager.address);
  console.log("vaultManager:", vaultManager.address);
  console.log("alice:", alice.address);

  console.log("==============");

  console.log("Native ETH balance (testStrategy):", formatEther(strategyEthBalance));
  console.log("Native ETH balance (diamond):", formatEther(diamondEthBalance));
  console.log("Native ETH balance (owner):", formatEther(ownerEthBalance));
  console.log("Native ETH balance (vaultManager):", formatEther(vaultManagerEthBalance));
  console.log("Native ETH balance (alice):", formatEther(aliceEthBalance));

  console.log("ethYieldToken balance (testStrategy):", formatEther(strategyBalance));
  console.log("ethYieldToken balance (diamond):", formatEther(diamondBalance));

  console.log("==============");

  const strategyAssetPrice = await testStrategy.previewExit(parseEther("1"));
  console.log("Strategy asset price (in ETH):", formatEther(strategyAssetPrice));

  console.log("==============");
  console.log("Stake Info:");

  const stakeInfo = await allocation.stakeInfo(testStrategy);
  console.log({
    totalStake: formatEther(stakeInfo.totalStake),
    totalAllocation: formatEther(stakeInfo.totalAllocation),
    pendingExitStake: formatEther(stakeInfo.pendingExitStake),
  });

  console.log("==============");
  console.log("Vault Info:");

  const vaultInfo = await hyperFactory.vaultInfo(testStrategy);
  console.log({
    enabled: vaultInfo.enabled,
    strategy: vaultInfo.strategy,
    stakeCurrency: vaultInfo.stakeCurrency.token,
    revenueAsset: vaultInfo.revenueAsset,
    feeRecipient: vaultInfo.feeRecipient,
    feeRate: formatEther(vaultInfo.feeRate),
    bridgeSafetyMargin: formatEther(vaultInfo.bridgeSafetyMargin),
  });

  console.log("==============");
  console.log("Lockbox data:");

  const lockboxData = await lockbox.lockboxData();
  console.log({
    mailbox: lockboxData.mailbox,
    ism: lockboxData.ism,
    destination: lockboxData.destination,
    lumiaFactory: lockboxData.lumiaFactory,
    lastMessage: lockboxData.lastMessage,
  });

  console.log("==============");
}

async function getUserFailedRedeems() {
  const { signers, lockbox } = await getContracts();
  const { alice } = signers;

  const userAddress = alice.address;

  const ids = await lockbox.getUserFailedRedeemIds(userAddress);

  console.log(`Failed redeem IDs for user ${userAddress}:`);
  console.log(JSON.stringify(
    ids.map((id) => id.toString()),
  ));

  const failedRedeems = await lockbox.getFailedRedeems([...ids]);
  for (let i = 0; i < ids.length; i++) {
    const redeem = failedRedeems[i];
    console.log(`Failed Redeem ID ${ids[i]}:`, {
      strategy: redeem.strategy,
      user: redeem.user,
      amount: formatEther(redeem.amount),
    });
  }
}

async function getUserLastClaims() {
  const { signers, deposit, testStrategy } = await getContracts();
  const { alice } = signers;

  const userAddress = alice.address;

  const limit = 10;
  const lastClaimIds = await deposit.lastClaims(testStrategy, userAddress, limit);

  console.log(`Last ${limit} claims for user ${userAddress} on strategy ${testStrategy.target}:`);
  console.log(JSON.stringify(
    lastClaimIds.map((id) => id.toString()),
  ));

  const claims = await deposit.pendingWithdraws([...lastClaimIds]);
  for (let i = 0; i < lastClaimIds.length; i++) {
    const claim = claims[i];
    console.log(`Claim ID ${lastClaimIds[i]}:`, {
      strategy: claim.strategy,
      unlockTime: new Date(Number(claim.unlockTime) * 1000).toISOString(),
      eligible: claim.eligible,
      expectedAmount: formatEther(claim.expectedAmount),
      feeWithdraw: claim.feeWithdraw,
    });
  }
}

async function cmdLumiaInfo() {
  const { signers, testStrategyAddress, lumiaDiamond, hyperlaneHandler } = await getBeamContracts();
  const { lumiaFactoryManager, alice } = signers;

  // native LUMIA balances
  const lumiaFactoryManagerLumiaBalance = await ethers.provider.getBalance(lumiaFactoryManager);
  const aliceLumiaBalance = await ethers.provider.getBalance(alice);

  console.log("=== Lumia Info ===");
  console.log("lumiaDiamond:", lumiaDiamond);
  console.log("hyperlaneHandler:", await hyperlaneHandler.getAddress());

  console.log("lumiaFactoryManager:", lumiaFactoryManager.address);

  const mailbox = await hyperlaneHandler.mailbox();
  console.log("mailbox:", mailbox);

  console.log("==============");

  console.log("Native LUMIA balance (lumiaFactoryManager):", formatEther(lumiaFactoryManagerLumiaBalance));
  console.log("Native LUMIA balance (alice):", formatEther(aliceLumiaBalance));

  console.log("==============");

  const routeInfo = await hyperlaneHandler.getRouteInfo(testStrategyAddress);
  if (routeInfo.exists) {
    console.log("Route Info for test strategy:");
    console.log({
      originDestination: routeInfo.originDestination,
      originLockbox: routeInfo.originLockbox,
      assetToken: routeInfo.assetToken,
      vaultShares: routeInfo.vaultShares,
    });

    const principial = await ethers.getContractAt(
      "LumiaPrincipal", routeInfo.assetToken,
    );
    const shares = await ethers.getContractAt(
      "LumiaVaultShares", routeInfo.vaultShares,
    );

    // total supplies
    const principalTotalSupply = await principial.totalSupply();
    const sharesTotalSupply = await shares.totalSupply();

    console.log("Lumia Principal total supply:", formatEther(principalTotalSupply));
    console.log("Lumia Vault Shares total supply:", formatEther(sharesTotalSupply));

    // alice shares balance
    const aliceSharesBalance = await shares.balanceOf(alice.address);
    console.log("Vault Shares balance (alice):", formatEther(aliceSharesBalance));
  } else {
    console.log("No route info for test strategy.");
  }
  console.log("==============");
}

// --- Main ---

async function main() {
  // hardhat script cant take args, so we use env var for command
  let command = process.env.CMD;
  if (!command) {
    command = "info"; // default command
  }

  switch (command) {
    // --- Management Commands ---

    case "add-strategy": {
      await cmdAddStrategy();
      break;
    }
    case "supply-strategy": {
      await cmdSupplyStrategy();
      break;
    }
    case "set-strategy-asset-price": {
      await cmdSetStrategyAssetPrice();
      break;
    }
    case "setup-lockbox": {
      await cmdSetupLockbox();
      break;
    }
    case "set-lockbox-ism": {
      await cmdSetLockboxISM();
      break;
    }
    case "set-fee-data": {
      await cmdSetFeeData();
      break;
    }
    case "setup-hyperlane-handler": {
      await cmdSetupHyperlaneHandler();
      break;
    }
    case "set-lumia-mailbox": {
      await cmdSetLumiaMailbox();
      break;
    }

    // --- Main Operations Commands ---

    case "report-revenue": {
      await cmdReportRevenue();
      break;
    }
    case "stake-deposit": {
      await cmdStakeDeposit();
      break;
    }
    case "shares-redeem": {
      await cmdSharesRedeem();
      break;
    }
    case "reexecute-failed-redeem": {
      await cmdReexecuteFailedRedeem();
      break;
    }
    case "claim-withdraw": {
      await cmdClaimWithdraw();
      break;
    }

    // --- Info Commands ---

    case "info": {
      await cmdInfo();
      break;
    }

    case "get-user-failed-redeems": {
      await getUserFailedRedeems();
      break;
    }

    case "get-user-last-claims": {
      await getUserLastClaims();
      break;
    }

    case "lumia-info": {
      await cmdLumiaInfo();
      break;
    }

    // --- Utility Commands ---

    case "send-ether": {
      const { signers } = await getContracts();
      await sendEther(
        signers.owner,
        signers.lumiaFactoryManager.address,
        "0.1",
      );
      break;
    }
    default:
      console.error(`Unknown command: ${command}`);
      process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
