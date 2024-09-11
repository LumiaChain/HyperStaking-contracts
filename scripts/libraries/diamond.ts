/*
 * base source: https://github.com/mudgen/diamond-3-hardhat/tree/main/scripts/libraries
 * library upgraded to ethers v6 and rewritten to typescript
 */

import { ethers, Interface, FunctionFragment, AddressLike, BytesLike } from "ethers";

export enum FacetCutAction {
  Add = 0,
  Replace = 1,
  Remove = 2,
}

export interface SelectorArray extends Array<string> {
  iface?: Interface;
  remove?: (selectors: SelectorArray, functionNames: string[]) => SelectorArray;
  get?: (selectors: SelectorArray, functionNames: string[]) => SelectorArray;
}

// get function selectors from ABI
export function getSelectors (iface: Interface): SelectorArray {
  const selectors: SelectorArray = [];

  for (const f of iface.fragments) {
    if (f.type === "function") {
      const functionFragment = f as FunctionFragment;
      selectors.push(functionFragment.selector);
    }
  }

  selectors.iface = iface;
  selectors.remove = remove;
  selectors.get = get;
  return selectors;
}

// get function selector from function signature
export function getSelector (func: string) {
  return FunctionFragment.from(func).selector;
}

// used with getSelectors to remove selectors from an array of selectors
// functionNames argument is an array of function signatures
export function remove (this: SelectorArray, functionNames: string[]): SelectorArray {
  const selectors: SelectorArray = this.filter((v) => {
    for (const functionName of functionNames) {
      if (v === this.iface?.getFunction(functionName)?.selector) {
        return false;
      }
    }
    return true;
  });

  selectors.iface = this.iface;
  selectors.remove = this.remove;
  selectors.get = this.get;
  return selectors;
}

// used with getSelectors to get selectors from an array of selectors
// functionNames argument is an array of function signatures
export function get (this: SelectorArray, functionNames: string[]): SelectorArray {
  const selectors: SelectorArray = this.filter((v) => {
    for (const functionName of functionNames) {
      if (v === this.iface?.getFunction(functionName)?.selector) {
        return true;
      }
    }
    return false;
  });
  selectors.iface = this.iface;
  selectors.remove = this.remove;
  selectors.get = this.get;
  return selectors;
}

// remove selectors using an array of signatures
export function removeSelectors (selectors: string[], signatures: string[]) {
  const iface = new ethers.Interface(signatures.map(v => "function " + v));
  const removeSelectors = signatures.map(v => iface.getFunction(v)?.selector);
  selectors = selectors.filter(v => !removeSelectors.includes(v));
  return selectors;
}

export type FacetStruct = {
  facetAddress: AddressLike;
  functionSelectors: BytesLike[];
};

// find a particular address position in the return value of diamondLoupeFacet.facets()
export function findAddressPositionInFacets (facetAddress: string, facets: FacetStruct[]) {
  for (let i = 0; i < facets.length; i++) {
    if (facets[i].facetAddress === facetAddress) {
      return i;
    }
  }
}
