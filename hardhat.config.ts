import { HardhatUserConfig, task } from "hardhat/config";

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
    },
    localhost: {
      url: process.env.LOCAL_RPC_URL,
      chainId: 31337,
    },
    // ethereum: {
    //   url: process.env.ETHEREUM_RPC_URL,
    //   chainId: 1,
    //   accounts: [process.env.DEPLOYER_PRIVATE_KEY!],
    //   gasPrice: 20e9, // 20 Gwei
    // },
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
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
