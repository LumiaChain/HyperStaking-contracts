import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther, keccak256, toUtf8Bytes } from "ethers";

import { ISuperRBAC } from "../../../typechain-types/contracts/external/superform/core/settings/SuperRBAC";

const HARDHAT_CHAIN_ID = 31337;

// Crates a test SuperVault, a mock used for integration tests
const SuperformMockModule = buildModule("SuperformMockModule", (m) => {
  const erc4626VaultAddress = m.getParameter("erc4626VaultAddress");
  const erc4626Vault = m.contractAt("TestERC4626", erc4626VaultAddress);

  const assetAddress = m.staticCall(erc4626Vault, "asset");
  const erc20Asset = m.contractAt("TestERC20", assetAddress);

  const symbol = m.staticCall(erc20Asset, "symbol");

  // -------

  const superManager = m.getAccount(0);
  const fields = [
    "admin", "emergencyAdmin", "paymentAdmin", "csrProcessor", "tlProcessor", "brProcessor",
    "csrUpdater", "srcVaaRelayer", "dstSwapper", "csrRescuer", "csrDisputer",
  ];
  const initRoles = Object.fromEntries(fields.map((key) => [key, superManager])) as unknown as ISuperRBAC.InitialRoleSetupStruct;

  const superRBAC = m.contract("SuperRBAC", [initRoles]);
  const superRegistry = m.contract("SuperRegistry", [superRBAC]);

  const superPositions = m.contract("SuperPositions", [
    "dynamicURI", superRegistry, "Super Test Positions", "STP",
  ]);
  const superVaultFactory = m.contract("SuperVaultFactory", [superRegistry, superManager]);
  const superformRouter = m.contract("SuperformRouter", [superRegistry]);
  const superformFactory = m.contract("SuperformFactory", [superRegistry]);

  // setup SuperRegistry
  const items = [
    { key: "SUPERFORM_ROUTER", object: superformRouter, chain: HARDHAT_CHAIN_ID },
    { key: "SUPER_POSITIONS", object: superPositions, chain: HARDHAT_CHAIN_ID },
    { key: "SUPERFORM_FACTORY", object: superformFactory, chain: HARDHAT_CHAIN_ID },
  ];

  m.call(
    superRegistry,
    "batchSetAddress",
    [
      items.map((item) => keccak256(toUtf8Bytes(item.key))),
      items.map((item) => item.object),
      items.map((item) => item.chain),
    ],
  );

  const stateRegistryId = 1;
  const setStateRegistryFuture = m.call(superRegistry, "setStateRegistryAddress", [
    [stateRegistryId], [superRegistry],
  ]);

  const erc4626Form = m.contract("ERC4626Form", [superRegistry], { after: [setStateRegistryFuture] });

  const formImplementationId = 3;
  const addFormFuture = m.call(superformFactory, "addFormImplementation", [
    erc4626Form, formImplementationId, stateRegistryId,
  ]);
  const createSuperformFuture = m.call(
    superformFactory,
    "createSuperform",
    [formImplementationId, erc4626Vault], { after: [addFormFuture] },
  );

  const superformId = m.staticCall(superformFactory, "vaultToSuperforms", [erc4626Vault, 0], 0, { after: [createSuperformFuture] });

  const testVaultName = "Test Super Vault " + symbol;
  const depositLimit = parseEther("256");
  const superformIds = [superformId];
  const startingWeights = [10_000];

  // -------

  const createSuperVault = m.call(superVaultFactory, "createSuperVault", [
    assetAddress,
    superManager,
    superManager,
    testVaultName,
    depositLimit,
    superformIds,
    startingWeights,
    formImplementationId,
  ], { from: superManager, after: [createSuperformFuture] });

  // -------

  const index = 0;
  const testSuperVaultAddress = m.staticCall(superVaultFactory, "superVaults", [index], 0, { after: [createSuperVault] });
  const superVault = m.contractAt("SuperVault", testSuperVaultAddress);

  return { superformFactory, superformRouter, superVault, superPositions };
});

export default SuperformMockModule;
