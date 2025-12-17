import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ZeroAddress } from "ethers";

const GauntletMockModule = buildModule("GauntletMockModule", (m) => {
  const owner = m.getAccount(0);
  const feeReceiver = m.getAccount(1);

  const usdcAddress = m.getParameter("usdcAddress");

  const oracleUpdateDelay = 604800; // 1 week

  const authority = m.contract("RolesAuthority", [
    owner,
    ZeroAddress,
  ]);

  const oracleRegistry = m.contract("OracleRegistry", [
    owner, // address initialOwner,
    authority, // Authority initialAuthority,
    oracleUpdateDelay, // uint256 oracleUpdateDelay
  ]);

  const aeraPriceAndFeeCalculator = m.contract("PriceAndFeeCalculator", [
    usdcAddress, // IERC20 numeraire,
    oracleRegistry, // IOracleRegistry oracleRegistry,
    owner, // address owner_,
    authority, // Authority authority_
  ]);

  const gauntletVaultDeployer = m.contract("GauntletVaultDeployer", [
    "Test USD Alpha", // name
    "gtUSDa", // symbol
    owner,
    authority,
    ZeroAddress, // IBeforeTransferHook
    aeraPriceAndFeeCalculator,
    usdcAddress, // asset
    feeReceiver,
  ]);

  const createVault = m.call(gauntletVaultDeployer, "deploy", [], {
    id: "createGauntletVault",
  });

  const multiDepositorVaultAddress = m.readEventArgument(
    createVault,
    "VaultDeployed",
    "vault",
    {
      emitter: gauntletVaultDeployer,
    },
  );

  const aeraProvisioner = m.contract("Provisioner", [
    aeraPriceAndFeeCalculator, // IPriceAndFeeCalculator priceAndFeeCalculator,
    multiDepositorVaultAddress, // address multiDepositorVault,
    owner, // address owner_,
    authority, // Authority authority_
  ], {
    after: [createVault],
  });

  const aeraMultiDepositorVault = m.contractAt("MultiDepositorVault", multiDepositorVaultAddress);

  m.call(aeraMultiDepositorVault, "acceptOwnership", [], { after: [createVault] });
  m.call(aeraMultiDepositorVault, "setProvisioner", [aeraProvisioner], { after: [createVault] });
  m.call(aeraPriceAndFeeCalculator, "setVaultAccountant", [aeraMultiDepositorVault, owner], { after: [createVault] });

  return { oracleRegistry, aeraProvisioner, aeraPriceAndFeeCalculator, aeraMultiDepositorVault };
});

export default GauntletMockModule;
