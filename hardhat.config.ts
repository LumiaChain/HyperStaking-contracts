import { HardhatUserConfig, task } from "hardhat/config";

import "@nomicfoundation/hardhat-toolbox";
import "hardhat-contract-sizer";
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
        version: "0.8.24",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          // viaIR: true,
        },
      },
    ],
  },

  defaultNetwork: "hardhat",
  networks: {
    hardhat: {},
    local: {
      url: process.env.LOCAL_RPC_URL,
      chainId: 31337,
      accounts: {
        mnemonic: process.env.WALLET_MNEMONIC,
      },
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL,
      accounts: {
        mnemonic: process.env.WALLET_MNEMONIC,
      },

      initialBaseFeePerGas: 2500000000,
      chainId: 11155111,
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
};

export default config;
