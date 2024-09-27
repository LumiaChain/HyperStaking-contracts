import {
  createWalletClient, custom, publicActions, Address, formatEther,
} from "viem";
import { useAccount } from "wagmi";

import { useState, useEffect } from "react";

const Staking = () => {
  const [blockNumber, setBlockNumber] = useState<bigint | null>(null);
  const [account, setAccount] = useState<Address | null>(null);
  const [accountHumanBalance, setAccountHumanBalance] = useState<string>("0.0");

  const [loading, setLoading] = useState(true);

  const { chain } = useAccount();
  const walletClient = createWalletClient({
    chain,
    transport: custom(window.ethereum!),
  }).extend(publicActions);

  useEffect(() => {
    const formatEtherBalance = (balance: bigint): string => {
      return parseFloat( // remove trailing zeros
        parseFloat( // to 8 decimal places
          formatEther(balance),
        ).toFixed(8),
      ).toString();
    };

    const getBalance = async (account: Address): Promise<bigint> => {
      const balance = await walletClient.getBalance({
        address: account,
      });

      return balance;
    };

    const fetchData = async () => {
      const blockNumber = await walletClient.getBlockNumber();
      setBlockNumber(blockNumber);
      console.log(blockNumber);

      const accounts = await walletClient.getAddresses();
      setAccount(accounts[0]);

      const balance = await getBalance(accounts[0]);
      setAccountHumanBalance(formatEtherBalance(balance));

      setLoading(false);
    };
    fetchData();
  }, [walletClient]);

  return (
    <div>
      <div className="flex flex-col text-2xl items-center justify-start h-[150px]">
        {
          loading
            ? (<div>Loading...</div>)
            : (<div>Sync: OK</div>)
        }
      </div>

      <div className="grid text-md gap-4 mx-auto w-[600px]">
        <div className="grid grid-cols-2 gap-2 mb-2 text-xl">
          <input type="text" className="border p-2 rounded-md text-black" placeholder="0"></input>
          <button className="bg-slate-700 rounded-md text-white p-2 font-semibold"> Stake </button>
          <div className="align-left text-sm"> Balance (ETH): {accountHumanBalance} <a>Max</a></div>
        </div>

        <div className="grid grid-cols-2 gap-2 mb-2 text-xl">
          <input type="text" className="border p-2 rounded-md text-black" placeholder="0"></input>
          <button className="bg-slate-700 rounded-md text-white p-2 font-semibold"> Unstake </button>
          <div className="align-left text-sm"> Stake (ETH): 0.003 <a>Max</a></div>
        </div>
      </div>

      <br />
      <br />

      <ol className="list-inside text-xl text-left font-[family-name:var(--font-geist-mono)]">
        <li className="mb-2">
          <b className="text-xl"> Stats: </b>
        </li>

        <li className="grid grid-cols-3 gap-2 mb-2">
          <code className="col-span-1 px-2 rounded font-medium"> Account:</code> <div className="col-span-2">{account?.toString()} </div>
          <code className="col-span-1 px-2 rounded font-medium"> Total Staked:</code> <div className="col-span-2">0.5 ETH</div>
          <code className="col-span-1 px-2 rounded font-medium"> Block Number:</code> <div className="col-span-2">{blockNumber?.toString()} </div>
        </li>

      </ol>

    </div>
  );
};

export default Staking;
