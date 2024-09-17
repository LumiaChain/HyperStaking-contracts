/* source: https://github.com/mudgen/diamond-3-hardhat */

import DiamondModule from "../ignition/modules/Diamond";
import {
  getSelectors,
  FacetCutAction,
  removeSelectors,
  findAddressPositionInFacets,
} from "../scripts/libraries/diamond";

import { assert } from "chai";
import { Contract } from "ethers";
import { ethers, ignition } from "hardhat";

import { DiamondCutFacet, OwnershipFacet } from "../typechain-types";
import { DiamondLoupeFacet } from "../typechain-types/diamond/facets";

describe("DiamondTest", async function () {
  let diamond: Contract;
  let diamondCutFacet: DiamondCutFacet;
  let diamondLoupeFacet: DiamondLoupeFacet;
  let ownershipFacet: OwnershipFacet;
  let tx;
  let receipt;
  let result;
  const addresses = new Array<string>();

  before(async function () {
    const deployment = await ignition.deploy(DiamondModule);
    diamond = deployment.diamond;
    diamondCutFacet = await ethers.getContractAt("DiamondCutFacet", diamond);
    diamondLoupeFacet = await ethers.getContractAt("DiamondLoupeFacet", diamond);
    ownershipFacet = await ethers.getContractAt("OwnershipFacet", diamond);
  });

  it("should have three facets -- call to facetAddresses function", async () => {
    for (const address of await diamondLoupeFacet.facetAddresses()) {
      addresses.push(address);
    }

    assert.equal(addresses.length, 3);
  });

  it("facets should have the right function selectors -- call to facetFunctionSelectors function", async () => {
    let selectors = getSelectors(diamondCutFacet.interface);
    result = await diamondLoupeFacet.facetFunctionSelectors(addresses[0]);
    assert.sameMembers([...result], selectors);

    selectors = getSelectors(diamondLoupeFacet.interface);
    result = await diamondLoupeFacet.facetFunctionSelectors(addresses[1]);
    assert.sameMembers([...result], selectors);

    selectors = getSelectors(ownershipFacet.interface);
    result = await diamondLoupeFacet.facetFunctionSelectors(addresses[2]);
    assert.sameMembers([...result], selectors);
  });

  it("selectors should be associated to facets correctly -- multiple calls to facetAddress function", async () => {
    assert.equal(
      addresses[0],
      await diamondLoupeFacet.facetAddress("0x1f931c1c"),
    );
    assert.equal(
      addresses[1],
      await diamondLoupeFacet.facetAddress("0xcdffacc6"),
    );
    assert.equal(
      addresses[1],
      await diamondLoupeFacet.facetAddress("0x01ffc9a7"),
    );
    assert.equal(
      addresses[2],
      await diamondLoupeFacet.facetAddress("0xf2fde38b"),
    );
  });

  it("should add test1 functions", async () => {
    const test1Facet = await ethers.deployContract("Test1Facet");
    addresses.push(await test1Facet.getAddress());
    const selectors = getSelectors(test1Facet.interface).remove(["supportsInterface(bytes4)"]);
    tx = await diamondCutFacet.diamondCut(
      [{
        facetAddress: test1Facet.target,
        action: FacetCutAction.Add,
        functionSelectors: selectors,
      }],
      ethers.ZeroAddress, "0x", { gasLimit: 800000 });
    receipt = await tx.wait();
    if (receipt && !receipt.status) {
      throw Error(`Diamond upgrade failed: ${tx.hash}`);
    }
    result = await diamondLoupeFacet.facetFunctionSelectors(test1Facet.target);
    assert.sameMembers([...result], selectors);
  });

  it("should test function call", async () => {
    const test1Facet = await ethers.getContractAt("Test1Facet", diamond);
    await test1Facet.test1Func10();
  });

  it("should replace supportsInterface function", async () => {
    const Test1Facet = await ethers.getContractFactory("Test1Facet");
    const selectors = getSelectors(Test1Facet.interface).get(["supportsInterface(bytes4)"]);
    const testFacetAddress = addresses[3];
    tx = await diamondCutFacet.diamondCut(
      [{
        facetAddress: testFacetAddress,
        action: FacetCutAction.Replace,
        functionSelectors: selectors,
      }],
      ethers.ZeroAddress, "0x", { gasLimit: 800000 });
    receipt = await tx.wait();
    if (receipt && !receipt.status) {
      throw Error(`Diamond upgrade failed: ${tx.hash}`);
    }
    const result = await diamondLoupeFacet.facetFunctionSelectors(testFacetAddress);
    assert.sameMembers([...result], getSelectors(Test1Facet.interface));
  });

  it("should add test2 functions", async () => {
    const test2Facet = await ethers.deployContract("Test2Facet");
    addresses.push(await test2Facet.getAddress());
    const selectors = getSelectors(test2Facet.interface);
    tx = await diamondCutFacet.diamondCut(
      [{
        facetAddress: test2Facet.target,
        action: FacetCutAction.Add,
        functionSelectors: selectors,
      }],
      ethers.ZeroAddress, "0x", { gasLimit: 800000 });
    receipt = await tx.wait();
    if (receipt && !receipt.status) {
      throw Error(`Diamond upgrade failed: ${tx.hash}`);
    }
    result = await diamondLoupeFacet.facetFunctionSelectors(test2Facet.target);
    assert.sameMembers([...result], selectors);
  });

  it("should remove some test2 functions", async () => {
    const test2Facet = await ethers.getContractAt("Test2Facet", diamond);
    const functionsToKeep = ["test2Func1()", "test2Func5()", "test2Func6()", "test2Func19()", "test2Func20()"];
    const selectors = getSelectors(test2Facet.interface).remove(functionsToKeep);
    tx = await diamondCutFacet.diamondCut(
      [{
        facetAddress: ethers.ZeroAddress,
        action: FacetCutAction.Remove,
        functionSelectors: selectors,
      }],
      ethers.ZeroAddress, "0x", { gasLimit: 800000 });
    receipt = await tx.wait();
    if (receipt && !receipt.status) {
      throw Error(`Diamond upgrade failed: ${tx.hash}`);
    }
    result = await diamondLoupeFacet.facetFunctionSelectors(addresses[4]);
    assert.sameMembers([...result], getSelectors(test2Facet.interface).get(functionsToKeep));
  });

  it("should remove some test1 functions", async () => {
    const test1Facet = await ethers.getContractAt("Test1Facet", diamond);
    const functionsToKeep = ["test1Func2()", "test1Func11()", "test1Func12()"];
    const selectors = getSelectors(test1Facet.interface).remove(functionsToKeep);
    tx = await diamondCutFacet.diamondCut(
      [{
        facetAddress: ethers.ZeroAddress,
        action: FacetCutAction.Remove,
        functionSelectors: selectors,
      }],
      ethers.ZeroAddress, "0x", { gasLimit: 800000 });
    receipt = await tx.wait();
    if (receipt && !receipt.status) {
      throw Error(`Diamond upgrade failed: ${tx.hash}`);
    }
    result = await diamondLoupeFacet.facetFunctionSelectors(addresses[3]);
    assert.sameMembers([...result], getSelectors(test1Facet.interface).get(functionsToKeep));
  });

  it("remove all functions and facets except 'diamondCut' and 'facets'", async () => {
    let selectors = [];
    let facets = await diamondLoupeFacet.facets();
    for (let i = 0; i < facets.length; i++) {
      selectors.push(...facets[i].functionSelectors);
    }
    selectors = removeSelectors(selectors, ["facets()", "diamondCut(tuple(address,uint8,bytes4[])[],address,bytes)"]);
    tx = await diamondCutFacet.diamondCut(
      [{
        facetAddress: ethers.ZeroAddress,
        action: FacetCutAction.Remove,
        functionSelectors: selectors,
      }],
      ethers.ZeroAddress, "0x", { gasLimit: 800000 });
    receipt = await tx.wait();
    if (receipt && !receipt.status) {
      throw Error(`Diamond upgrade failed: ${tx.hash}`);
    }
    facets = await diamondLoupeFacet.facets();
    assert.equal(facets.length, 2);
    assert.equal(facets[0][0], addresses[0]);
    assert.sameMembers([...facets[0][1]], ["0x1f931c1c"]);
    assert.equal(facets[1][0], addresses[1]);
    assert.sameMembers([...facets[1][1]], ["0x7a0ed627"]);
  });

  it("add most functions and facets", async () => {
    const diamondLoupeFacetSelectors = getSelectors(diamondLoupeFacet.interface).remove(["supportsInterface(bytes4)"]);

    const ownershipFacet = await ethers.deployContract("OwnershipFacet");
    const Test1Facet = await ethers.getContractFactory("Test1Facet");
    const Test2Facet = await ethers.getContractFactory("Test2Facet");

    // Any number of functions from any number of facets can be added/replaced/removed in a
    // single transaction
    const cut = [
      {
        facetAddress: addresses[1],
        action: FacetCutAction.Add,
        functionSelectors: diamondLoupeFacetSelectors.remove(["facets()"]),
      },
      {
        facetAddress: addresses[2],
        action: FacetCutAction.Add,
        functionSelectors: getSelectors(ownershipFacet.interface),
      },
      {
        facetAddress: addresses[3],
        action: FacetCutAction.Add,
        functionSelectors: getSelectors(Test1Facet.interface),
      },
      {
        facetAddress: addresses[4],
        action: FacetCutAction.Add,
        functionSelectors: getSelectors(Test2Facet.interface),
      },
    ];

    tx = await diamondCutFacet.diamondCut(cut, ethers.ZeroAddress, "0x", { gasLimit: 8000000 });
    receipt = await tx.wait();
    if (receipt && !receipt.status) {
      throw Error(`Diamond upgrade failed: ${tx.hash}`);
    }

    const facets = await diamondLoupeFacet.facets();

    const facetAddresses = await diamondLoupeFacet.facetAddresses();
    assert.equal(facetAddresses.length, 5);
    assert.equal(facets.length, 5);
    assert.sameMembers([...facetAddresses], addresses);
    assert.equal(facets[0][0], facetAddresses[0], "first facet");
    assert.equal(facets[1][0], facetAddresses[1], "second facet");
    assert.equal(facets[2][0], facetAddresses[2], "third facet");
    assert.equal(facets[3][0], facetAddresses[3], "fourth facet");
    assert.equal(facets[4][0], facetAddresses[4], "fifth facet");
    assert.sameMembers([...facets[findAddressPositionInFacets(addresses[0], facets)][1]], getSelectors(diamondCutFacet.interface));
    assert.sameMembers([...facets[findAddressPositionInFacets(addresses[1], facets)][1]], diamondLoupeFacetSelectors);
    assert.sameMembers([...facets[findAddressPositionInFacets(addresses[2], facets)][1]], getSelectors(ownershipFacet.interface));
    assert.sameMembers([...facets[findAddressPositionInFacets(addresses[3], facets)][1]], getSelectors(Test1Facet.interface));
    assert.sameMembers([...facets[findAddressPositionInFacets(addresses[4], facets)][1]], getSelectors(Test2Facet.interface));
  });
});
