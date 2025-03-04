import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "ethers";

// Crates a test 3adao lending protocol, a mock used for tests
const ThreeADaoMockModule = buildModule("ThreeADaoMockModule", (m) => {
  const feeRecipient = m.getAccount(1);

  const rwaUSD = m.contract("MintableToken", ["rwaUSD", "rwaUSD"]);
  const rwaUSDOwner = m.contract("MintableTokenOwner", [rwaUSD]);
  const nativeWrapped = m.contract("WLumia", []);
  const tokenToPriceFeed = m.contract("TokenToPriceFeed", []);

  const rewardFee = 0;
  const smartVaultProxy = m.contract("SmartVaultProxy", [rewardFee]);
  const vaultExtraSettings = m.contract("VaultExtraSettings", []);
  const vaulDeployer = m.contract("SmartVaultDeployer", [vaultExtraSettings, smartVaultProxy]);

  const liquidationRouter = m.contract("LiquidationRouter", []);
  const vaultBorrowRate = m.contract("VaultBorrowRate", []);
  const borrowFeeRecipient = feeRecipient;
  const redemptionFeeRecipient = feeRecipient;

  // -------

  const vaultFactory = m.contract("VaultFactory", [
    rwaUSDOwner,
    nativeWrapped,
    tokenToPriceFeed,
    vaulDeployer,
    liquidationRouter,
    vaultBorrowRate,
    borrowFeeRecipient,
    redemptionFeeRecipient,
  ]);

  // -------

  m.call(rwaUSD, "transferOwnership", [rwaUSDOwner]);
  m.call(rwaUSDOwner, "addMinter", [vaultFactory]);

  const debtTreshold = 0;
  const maxRedeemablePercentage = parseEther("1");
  m.call(vaultExtraSettings, "setMaxRedeemablePercentage", [
    debtTreshold,
    maxRedeemablePercentage,
  ]);

  // -------

  return { rwaUSD, rwaUSDOwner, threeAVaultFactory: vaultFactory, tokenToPriceFeed };
});

export default ThreeADaoMockModule;
