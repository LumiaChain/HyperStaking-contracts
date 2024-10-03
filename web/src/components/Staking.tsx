import { useRef, useState, useEffect, useCallback } from "react";
import { useAccount } from "wagmi";
import { createWalletClient, custom, publicActions, Address, parseEther } from "viem";

import {
  getStaking, getVault, getUserPoolInfo, getPoolInfo, stakeDeposit, stakeWithdraw,
  formatEtherBalance, getAutoPxEth, getAutoPxEthVaultBalance,
  getUserStrategyContribution, formatSolidityPercentage, SolidityBytes,
} from "@/actions/web3-actions";

import Loading from "./Loading";

interface LoadingComponentRef {
  addLoadingMsg: (message: string) => number;
  removeLoadingMsg: (id: number) => void;
}

const Staking: React.FC = () => {
  const loadingRef = useRef<LoadingComponentRef>(null);

  const [blockNumber, setBlockNumber] = useState<bigint | null>(null);
  const intervalRef = useRef<NodeJS.Timeout | null>(null); // To store the interval ID
  const [init, setInit] = useState(true);

  // const [account, setAccount] = useState<Address | null>(null);
  const [accountHumanBalance, setAccountHumanBalance] = useState<string>("0.00");
  const [accountHumanStake, setAccountHumanStake] = useState<string>("0.00");
  const [accountContrib, setAccountContrib] = useState<string>("0.00");

  const [inputStakeBalance, setInputStakeBalance] = useState<string>("");
  const [inputUnstakeBalance, setInputUnstakeBalance] = useState<string>("");
  const [totalStake, setTotalStake] = useState<string>("");
  const [vaultApxEth, setVaultApxEth] = useState<string>("");

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
  const vault = getVault(walletClient);

  // ----- Show loading status -----

  const handleLoadingJob = async (loadingMessage: string, asyncJob: () => Promise<void>) => {
    const loadingId = loadingRef.current?.addLoadingMsg(loadingMessage);

    try {
      await asyncJob(); // Wait for the async function to complete
    } finally {
      // Ensure the loading message lasts at least 1 second
      if (loadingId !== undefined) {
        setTimeout(() => {
          loadingRef.current?.removeLoadingMsg(loadingId);
        }, 1000);
      }
    }
  };

  // ----- Set Functions -----

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

  const getUserContrib = useCallback(async (): Promise<bigint> => {
    return getUserStrategyContribution(vault, account);
  }, [vault, account]);

  // ----- Update Functions -----

  const updateBlockNumber = useCallback(async () => {
    await handleLoadingJob("Fetching block number...", async () => {
      const blockNumber = await walletClient.getBlockNumber();
      setBlockNumber(blockNumber);
    });
  }, [walletClient]);

  const updateStakeValues = useCallback(async () => {
    await handleLoadingJob("Fetching stake balances...", async () => {
      // const accounts = await walletClient.getAddresses();
      // setAccount(accounts[0]);

      const nativeBalance = await getNativeBalance();
      setAccountHumanBalance(formatEtherBalance(nativeBalance));

      const stakeBalance = await getUserStake();
      setAccountHumanStake(formatEtherBalance(stakeBalance));

      const contrib = await getUserContrib();
      setAccountContrib(formatSolidityPercentage(contrib));

      const totalStake = await getTotalStake();
      setTotalStake(formatEtherBalance(totalStake));

      const vaultApxEth = await getVaultApxEth();
      setVaultApxEth(formatEtherBalance(vaultApxEth));
    });
  }, [getNativeBalance, getUserStake, getTotalStake, getVaultApxEth, getUserContrib]);

  const waitForStakeAction = async (hash: SolidityBytes) => {
    const receipt = await walletClient.waitForTransactionReceipt({ hash });
    if (receipt.status === "success") {
      console.log("Transaction confirmed");
      await updateStakeValues(); // Call your function to fetch updated values
    } else {
      console.log("Transaction failed");
    }
  };

  // ----- Write Functions -----

  const stake = async () => {
    try {
      const amount = parseEther(inputStakeBalance);
      const hash = await stakeDeposit(staking, amount, account);
      setInputStakeBalance("");

      await handleLoadingJob("Waiting for stake tx confirmation...", async () => {
        await waitForStakeAction(hash);
      });
      await updateStakeValues();
    } catch (error) {
      console.error("Error staking:", error);
    }
  };

  const unstake = async () => {
    try {
      const amount = parseEther(inputUnstakeBalance);
      const hash = await stakeWithdraw(staking, amount, account);
      setInputUnstakeBalance("");

      await handleLoadingJob("Waiting for unstake tx confirmation...", async () => {
        await waitForStakeAction(hash);
      });
      await updateStakeValues();
    } catch (error) {
      console.error("Error unstaking:", error);
    }
  };

  useEffect(() => {
    if (init) {
      console.log("init");
      // Immediately fetch block number and stake values on mount
      updateBlockNumber();
      updateStakeValues();
      setInit(false);
    }

    if (!intervalRef.current) {
      // Set the interval to fetch the block number every 10 seconds
      intervalRef.current = setInterval(updateBlockNumber, 10000);
    }

    // Clean up the interval when the component unmounts
    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null; // Reset the interval ref
      }
    };
  }, [init, updateBlockNumber, updateStakeValues]);

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
      <Loading ref={loadingRef} />

      <br />

      <div className="grid text-md gap-4 mx-auto w-[450px]">
        <div className="grid grid-cols-3 gap-2 mb-2 text-md ">
          <input
            type="text"
            className="col-span-2 border p-2 rounded-md text-black"
            placeholder="0.0"
            value={inputStakeBalance}
            onChange={(e) => setInputStakeBalance(e.target.value)}
          />
          <button
            className="bg-slate-700 rounded-md text-white p-2 font-semibold"
            onClick={stake}
          >
            Stake
          </button>
          <div className="col-span-2 align-left text-sm">
            <span> Balance (ETH): {accountHumanBalance} </span>
            <button
              className="text-blue-500 font-semibold hover:text-blue-700"
              onClick={setMaxInputStake}
            >
              Max
            </button>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-2 mb-2 text-md">
          <input
            type="text"
            className="col-span-2 border p-2 rounded-md text-black"
            placeholder="0.0"
            value={inputUnstakeBalance}
            onChange={(e) => setInputUnstakeBalance(e.target.value)}
          />
          <button
            className="bg-slate-700 rounded-md text-white p-2 font-semibold"
            onClick={unstake}
          >
              Unstake
          </button>
          <div className="col-span-2 align-left text-sm">
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

      <ol className="list-inside text-md text-left font-[family-name:var(--font-geist-mono)]">
        <li className="mb-2">
          <b className="text-xl"> Account: </b>
        </li>

        <li className="grid grid-cols-3 gap-2 mb-2">
          <code className="col-span-1 px-2 rounded font-medium"> Address:</code> <div className="col-span-2">{account.toString()}</div>
          <code className="col-span-1 px-2 rounded font-medium"> ETH Balance:</code> <div className="col-span-2">{accountHumanBalance} ETH</div>
          <code className="col-span-1 px-2 rounded font-medium"> Stake Locked:</code> <div className="col-span-2">{accountHumanStake} ETH</div>
          <code className="col-span-1 px-2 rounded font-medium"> User Contribution:</code> <div className="col-span-2">{accountContrib} %</div>
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
