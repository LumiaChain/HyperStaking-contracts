import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ignition } from "hardhat";

import ThreeADaoMockModule from "../ignition/modules/test/3adaoMock";

describe("3adao-lumia", function () {
  async function getMocked3adao() {
    const { rwaUSD, ThreeAVaultFactory } = await ignition.deploy(ThreeADaoMockModule);
    return { rwaUSD, ThreeAVaultFactory };
  };

  describe("Mock", function () {
    it("test1", async function () {
      const { rwaUSD, ThreeAVaultFactory } = await loadFixture(getMocked3adao);
      console.log("rwaUSD", rwaUSD.target);
      console.log("3aVaultFactory", ThreeAVaultFactory.target);
    });
  });
});
