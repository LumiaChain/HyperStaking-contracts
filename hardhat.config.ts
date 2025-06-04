import { HardhatUserConfig, task } from "hardhat/config";
import { parseUnits } from "ethers";

import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "@typechain/hardhat";
import "hardhat-contract-sizer";
import "hardhat-switch-network";
import "solidity-docgen";

import dotenv from "dotenv";
dotenv.config();

const reportGas = process.env.REPORT_GAS?.toLowerCase() === "true";
const reportSize = process.env.REPORT_SIZE?.toLowerCase() === "true";

// If FORK=true, build a forking config; otherwise undefined.
const FORK = process.env.FORK === "true";
const forkingConfig = FORK
  ? {
      url: process.env.ETHEREUM_RPC_URL,
      blockNumber: 22_000_000,
    }
  : undefined;

task("accounts", "Prints the list of accounts with balances", async (_, hre): Promise<void> => {
  const accounts = await hre.ethers.getSigners();
  for (const account of accounts) {
    const balance = await hre.ethers.provider.getBalance(
      account.address,
    );
    console.log(`${account.address} - ${hre.ethers.formatUnits(balance, 18)} ETH`);
  }
});

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.27",
        settings: {
          evmVersion: "cancun",
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
  },

  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      allowBlocksWithSameTimestamp: true,
      forking: forkingConfig,
    },
    localhost: {
      url: process.env.LOCAL_RPC_URL,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY!],
      chainId: 31337,
    },
    ethereum: {
      url: process.env.ETHEREUM_RPC_URL,
      chainId: 1,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY!],
      ignition: {
        maxPriorityFeePerGas: parseUnits("0.1", "gwei"), // 0.1 Gwei
        maxFeePerGasLimit: parseUnits("15.0", "gwei"), // 15 Gwei
        // (optional) legacy‐style fallback
        // gasPrice: ...,
        // disableFeeBumping: false, (default: false)
      },
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL,
      chainId: 11155111,
      accounts: {
        mnemonic: process.env.WALLET_MNEMONIC,
      },
    },
    holesky: {
      url: process.env.HOLESKY_RPC_URL,
      chainId: 17000,
      accounts: {
        mnemonic: process.env.WALLET_MNEMONIC,
      },
    },
    // lumia_mainnet: {
    //   url: process.env.LUMIA_MAINNET_RPC_URL,
    //   chainId: 994873017,
    //   accounts: [process.env.DEPLOYER_PRIVATE_KEY!],
    // },
    lumia_testnet: {
      url: process.env.LUMIA_TESTNET_RPC_URL,
      chainId: 1952959480,
      accounts: {
        mnemonic: process.env.WALLET_MNEMONIC,
      },
    },
    bsc_testnet: {
      url: process.env.BSC_TESTNET_RPC_URL,
      chainId: 97,
      accounts: {
        mnemonic: process.env.WALLET_MNEMONIC,
      },
    },
  },

  mocha: {
    timeout: 200_000, // 200 seconds
  },

  gasReporter: {
    currency: "USD",
    coinmarketcap: process.env.COINMARKETCAP_KEY,
    enabled: reportGas,
  },

  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: reportSize,
    strict: true,

    // IGNORE these contracts:
    except: [
      "external",
    ],
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
