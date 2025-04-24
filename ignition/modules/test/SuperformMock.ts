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

  // ------- Form Implementations

  const formImplementationId = 1;
  const erc4626Form = m.contract("ERC4626Form", [superRegistry], { after: [setStateRegistryFuture] });

  const addForm4626 = m.call(superformFactory, "addFormImplementation", [
    erc4626Form, formImplementationId, stateRegistryId,
  ], { id: "addForm4626" });

  const formImplementationId5115 = 2;

  const erc5115Form = m.contract("ERC5115Form", [superRegistry], {
    id: "erc5115Form",
    after: [setStateRegistryFuture],
  });

  const addForm5115 = m.call(superformFactory, "addFormImplementation", [
    erc5115Form,
    formImplementationId5115,
    stateRegistryId,
  ], {
    id: "addForm5115",
    after: [erc5115Form],
  });

  // ------- Create Sub Superform (to put inside SuperVault)

  const createSubSuperformFuture = m.call(
    superformFactory,
    "createSuperform",
    [formImplementationId, erc4626Vault], { id: "superform1", after: [addForm4626] },
  );

  const subSuperformId = m.staticCall(superformFactory, "vaultToSuperforms", [erc4626Vault, 0], 0, { after: [createSubSuperformFuture] });

  // ------- Create SuperVault

  const testVaultName = "Test Super Vault " + symbol;
  const depositLimit = parseEther("256");
  const superformIds = [subSuperformId];
  const startingWeights = [10_000];

  const createSuperVault = m.call(superVaultFactory, "createSuperVault", [
    assetAddress,
    superManager,
    superManager,
    testVaultName,
    depositLimit,
    superformIds,
    startingWeights,
    formImplementationId5115,
  ], {
    from: superManager,
    id: "createSuperVault",
    after: [createSubSuperformFuture, addForm5115],
  });

  const superVaultAddress = m.readEventArgument(
    createSuperVault,
    "SuperVaultCreated",
    "superVault",
    {
      emitter: superVaultFactory,
    });

  // take over the management over supervault
  const tokenizedStrategy = m.contractAt("ITokenizedStrategy", superVaultAddress);
  m.call(tokenizedStrategy, "acceptManagement", [], {
    from: superManager, id: "acceptManagement", after: [createSuperVault],
  });

  const superVault = m.contractAt("SuperVault", superVaultAddress);

  // ------- Create Main Superform (representing SuperVault)

  m.call(
    superformFactory,
    "createSuperform",
    [formImplementationId, superVault], { id: "superformMain", after: [createSuperVault] },
  );

  // ---

  return { superformFactory, superformRouter, superVault, superPositions };
});

export default SuperformMockModule;
