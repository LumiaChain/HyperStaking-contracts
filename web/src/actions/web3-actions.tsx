import { Address, WalletClient, formatEther, getContract, GetContractReturnType, formatUnits } from "viem";

import IStaking from "@/contracts/artifacts/contracts/hyperstaking/interfaces/IStaking.sol/IStaking.json";
import IStrategyVault from "@/contracts/artifacts/contracts/hyperstaking/interfaces/IStrategyVault.sol/IStrategyVault.json";
import AutoPxEth from "@/contracts//artifacts/contracts/external/pirex/AutoPxEth.sol/AutoPxEth.json";

import { UserPoolInfoStruct, StakingPoolInfoStruct } from "@/contracts/typechain-types/contracts/hyperstaking/interfaces/IStaking";
import { UserVaultInfoStruct, VaultInfoStruct, VaultAssetStruct } from "@/contracts/typechain-types/contracts/hyperstaking/interfaces/IStrategyVault";

export type SolidityBytes = `0x${string}`;

// -- Utils --

export const formatEtherBalance = (balance: bigint): string => {
  return parseFloat( // remove trailing zeros
    parseFloat( // to 8 decimal places
      formatEther(balance),
    ).toFixed(8),
  ).toString();
};

// where precission is 1e18
export const formatSolidityPercentage = (balance: bigint): string => {
  return parseFloat(
    parseFloat(
      formatUnits(balance, 16),
    ).toFixed(2),
  ).toString();
};

// -- Staking Pools --

export const getStaking = (walletClient: WalletClient) => getContract({
  address: process.env.NEXT_PUBLIC_LUMIA_DIAMOND_ADDRESS as Address,
  abi: IStaking.abi,
  client: walletClient,
});

export const getUserPoolInfo = async (
  staking: GetContractReturnType<typeof IStaking.abi, WalletClient>,
  account: Address): Promise<UserPoolInfoStruct> => {
  return staking.read.userPoolInfo([
    process.env.NEXT_PUBLIC_STAKING_POOL_ID,
    account,
  ]) as Promise<UserPoolInfoStruct>;
};

export const getPoolInfo = async (
  staking: GetContractReturnType<typeof IStaking.abi, WalletClient>)
    : Promise<StakingPoolInfoStruct> => {
  return staking.read.poolInfo([
    process.env.NEXT_PUBLIC_STAKING_POOL_ID,
  ]) as Promise<StakingPoolInfoStruct>;
};

export const stakeDeposit = async (
  staking: GetContractReturnType<typeof IStaking.abi, WalletClient>,
  amount: bigint,
  account: Address,
): Promise<SolidityBytes> => {
  const hash = await staking.write.stakeDeposit([
    process.env.NEXT_PUBLIC_STAKING_POOL_ID,
    process.env.NEXT_PUBLIC_DINERO_STRATEGY_ADDRESS as Address,
    amount,
    account,
  ], {
    value: amount,
  });

  console.log("stakeDeposit hash:", hash);
  return hash;
};

export const stakeWithdraw = async (
  staking: GetContractReturnType<typeof IStaking.abi, WalletClient>,
  amount: bigint,
  account: Address,
): Promise<SolidityBytes> => {
  const hash = await staking.write.stakeWithdraw([
    process.env.NEXT_PUBLIC_STAKING_POOL_ID,
    process.env.NEXT_PUBLIC_DINERO_STRATEGY_ADDRESS as Address,
    amount,
    account,
  ]);

  console.log("stakeWithdraw hash:", hash);
  return hash;
};

// -- Strategy Vault --

export const getVault = (walletClient: WalletClient) => getContract({
  address: process.env.NEXT_PUBLIC_LUMIA_DIAMOND_ADDRESS as Address,
  abi: IStrategyVault.abi,
  client: walletClient,
});

export const getUserVaultInfo = async (
  vault: GetContractReturnType<typeof IStrategyVault.abi, WalletClient>,
  account: Address): Promise<UserVaultInfoStruct> => {
  return vault.read.userVaultInfo([
    process.env.NEXT_PUBLIC_DINERO_STRATEGY_ADDRESS,
    account,
  ]) as Promise<UserVaultInfoStruct>;
};

export const getUserStrategyContribution = async (
  vault: GetContractReturnType<typeof IStrategyVault.abi, WalletClient>,
  account: Address): Promise<bigint> => {
  return vault.read.userContribution([
    process.env.NEXT_PUBLIC_DINERO_STRATEGY_ADDRESS,
    account,
  ]) as Promise<bigint>;
};

export const getVaultInfo = async (
  vault: GetContractReturnType<typeof IStrategyVault.abi, WalletClient>)
    : Promise<VaultInfoStruct> => {
  return vault.read.vaultInfo([
    process.env.NEXT_PUBLIC_DINERO_STRATEGY_ADDRESS,
  ]) as Promise<VaultInfoStruct>;
};

export const getVaultAssetInfo = async (
  vault: GetContractReturnType<typeof IStrategyVault.abi, WalletClient>)
    : Promise<VaultAssetStruct> => {
  return vault.read.vaultInfo([
    process.env.NEXT_PUBLIC_DINERO_STRATEGY_ADDRESS,
  ]) as Promise<VaultAssetStruct>;
};

// -- Pirex --

export const getAutoPxEth = (walletClient: WalletClient) => getContract({
  address: process.env.NEXT_PUBLIC_APXETH_ADDRESS as Address,
  abi: AutoPxEth.abi,
  client: walletClient,
});

export const getAutoPxEthVaultBalance = async (
  autoPxEth: GetContractReturnType<typeof AutoPxEth.abi, WalletClient>): Promise<bigint> => {
  return autoPxEth.read.balanceOf([
    process.env.NEXT_PUBLIC_LUMIA_DIAMOND_ADDRESS as Address,
  ]) as Promise<bigint>;
};
