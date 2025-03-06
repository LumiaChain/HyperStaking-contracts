import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Crates a test rwa asset, based on 3adao Mintable Token implementation
const TestRwaAssetModule = buildModule("TestRwaAssetModule", (m) => {
  const name = m.getParameter("name", "rwaUSD");
  const symbol = m.getParameter("symbol", "rwaUSD");

  const rwaAsset = m.contract("MintableToken", [name, symbol]);
  const rwaAssetOwner = m.contract("MintableTokenOwner", [rwaAsset]);

  m.call(rwaAsset, "transferOwnership", [rwaAssetOwner]);

  return { rwaAsset, rwaAssetOwner };
});

export default TestRwaAssetModule;
