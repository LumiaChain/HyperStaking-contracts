import { useState, useEffect, useCallback } from "react";
import { useAccount } from "wagmi";
import { createWalletClient, custom, publicActions, Address, parseEther } from "viem";

import {
  getStaking, getUserPoolInfo, getPoolInfo, stakeDeposit, stakeWithdraw,
  formatEtherBalance, getAutoPxEth, getAutoPxEthVaultBalance,
} from "@/actions/web3-actions";

const Staking = () => {
  const [blockNumber, setBlockNumber] = useState<bigint | null>(null);
  // const [account, setAccount] = useState<Address | null>(null);
  const [accountHumanBalance, setAccountHumanBalance] = useState<string>("0.00");
  const [accountHumanStake, setAccountHumanStake] = useState<string>("0.00");

  const [inputStakeBalance, setInputStakeBalance] = useState<string>("0.0");
  const [inputUnstakeBalance, setInputUnstakeBalance] = useState<string>("0.0");
  const [totalStake, setTotalStake] = useState<string>("");
  const [vaultApxEth, setVaultApxEth] = useState<string>("");

  const [loading, setLoading] = useState(true);

  const { address, chain } = useAccount();
  const account = address as Address;

  const poolId = process.env.NEXT_PUBLIC_STAKING_POOL_ID;
  const strategyAddress = process.env.NEXT_PUBLIC_DINERO_STRATEGY_ADDRESS as Address;

  const walletClient = createWalletClient({
    chain,
    transport: custom(window.ethereum!),
    account,
  }).extend(publicActions);

  const staking = getStaking(walletClient);
  const autoPxEth = getAutoPxEth(walletClient);
  // const vault = getVault(walletClient);

  const getNativeBalance = useCallback(async (): Promise<bigint> => {
    return walletClient.getBalance({
      address: account,
    });
  }, [walletClient, account]);

  const getUserStake = useCallback(async (): Promise<bigint> => {
    const userPoolInfo = await getUserPoolInfo(staking, account);
    return BigInt(userPoolInfo.staked);
  }, [staking, account]);

  const getTotalStake = useCallback(async (): Promise<bigint> => {
    const poolInfo = await getPoolInfo(staking);
    return BigInt(poolInfo.totalStake);
  }, [staking]);

  const getVaultApxEth = useCallback(async (): Promise<bigint> => {
    return getAutoPxEthVaultBalance(autoPxEth);
  }, [autoPxEth]);

  const stake = async () => {
    const amount = parseEther(inputStakeBalance);
    await stakeDeposit(staking, amount, account);
  };

  const unstake = async () => {
    const amount = parseEther(inputUnstakeBalance);
    await stakeWithdraw(staking, amount, account);
  };

  useEffect(() => {
    const fetchData = async () => {
      const blockNumber = await walletClient.getBlockNumber();
      setBlockNumber(blockNumber);

      // const accounts = await walletClient.getAddresses();
      // setAccount(accounts[0]);

      const balance = await getNativeBalance();
      setAccountHumanBalance(formatEtherBalance(balance));

      const stake = await getUserStake();
      setAccountHumanStake(formatEtherBalance(stake));

      const totalStake = await getTotalStake();
      setTotalStake(formatEtherBalance(totalStake));

      const vaultApxEth = await getVaultApxEth();
      setVaultApxEth(formatEtherBalance(vaultApxEth));

      setLoading(false);
    };
    fetchData();
  }, [
    walletClient,
    getNativeBalance,
    getUserStake,
    getTotalStake,
    getVaultApxEth,
  ]);

  const setMaxInputStake = async () => {
    const balance = await getNativeBalance();
    if (balance === 0n) {
      return;
    }
    setInputStakeBalance(formatEtherBalance(balance));
  };

  const setMaxInputUnstake = async () => {
    const stake = await getUserStake();
    setInputUnstakeBalance(formatEtherBalance(stake));
  };

  return (
    <div>
      <div className="flex flex-col text-xl font-semibold items-center justify-start h-[150px]">
        {
          loading
            ? (<div>Loading...</div>)
            : (<div>Sync: OK</div>)
        }
      </div>

      <div className="grid text-md gap-4 mx-auto w-[600px]">
        <div className="grid grid-cols-2 gap-2 mb-2 text-xl">
          <input
            type="text"
            className="border p-2 rounded-md text-black"
            placeholder="0"
            value={inputStakeBalance}
            onChange={(e) => setInputStakeBalance(e.target.value)}
          />
          <button
            className="bg-slate-700 rounded-md text-white p-2 font-semibold"
            onClick={stake}
          >
            Stake
          </button>
          <div className="align-left text-sm">
            <span> Balance (ETH): {accountHumanBalance} </span>
            <button
              className="text-blue-500 font-semibold hover:text-blue-700"
              onClick={setMaxInputStake}
            >
              Max
            </button>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2 mb-2 text-xl">
          <input
            type="text"
            className="border p-2 rounded-md text-black"
            placeholder="0"
            value={inputUnstakeBalance}
            onChange={(e) => setInputUnstakeBalance(e.target.value)}
          />
          <button
            className="bg-slate-700 rounded-md text-white p-2 font-semibold"
            onClick={unstake}
          >
              Unstake
          </button>
          <div className="align-left text-sm">
            <span> Stake (ETH): {accountHumanStake} </span>
            <button
              className="text-blue-500 font-semibold hover:text-blue-700"
              onClick={setMaxInputUnstake}
            >
              Max
            </button>
          </div>
        </div>

      </div>

      <br />
      <br />

      <ol className="list-inside text-xl text-left font-[family-name:var(--font-geist-mono)]">
        <li className="mb-2">
          <b className="text-xl"> Account: </b>
        </li>

        <li className="grid grid-cols-3 gap-2 mb-2">
          <code className="col-span-1 px-2 rounded font-medium"> Address:</code> <div className="col-span-2">{account.toString()}</div>
          <code className="col-span-1 px-2 rounded font-medium"> ETH Balance:</code> <div className="col-span-2">{accountHumanBalance} ETH</div>
          <code className="col-span-1 px-2 rounded font-medium"> Stake Locked:</code> <div className="col-span-2">{accountHumanStake} ETH</div>
        </li>

        <br />
        <hr />
        <br />

        <li className="mb-2">
          <b className="text-xl"> Stats: </b>
        </li>

        <li className="grid grid-cols-3 gap-2 mb-2">
          <code className="col-span-1 px-2 rounded font-medium"> PoolId:</code> <div className="col-span-2">{poolId}</div>
          <code className="col-span-1 px-2 rounded font-medium"> Strategy:</code> <div className="col-span-2">{strategyAddress}</div>
          <code className="col-span-1 px-2 rounded font-medium"> Total Staked:</code> <div className="col-span-2">{totalStake} ETH</div>
          <code className="col-span-1 px-2 rounded font-medium"> Vault (apxETH):</code> <div className="col-span-2">{vaultApxEth} apxETH</div>
          <code className="col-span-1 px-2 rounded font-medium"> Block Number:</code> <div className="col-span-2">{blockNumber?.toString()}</div>
        </li>

      </ol>

    </div>
  );
};

export default Staking;
