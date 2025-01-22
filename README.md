# HyperStaking Contracts

This repository contains the HyperStaking contracts, built using Hardhat for testing, deployment, and development. The contracts utilize the Diamond Proxy architecture (ERC-2535).

## Project Overview

This project introduces multiple staking pools and a range of yield-generating strategies, allowing users to stake various tokens into different pools. The system is designed to easily accommodate new pools and strategies as needed.

### Key Features:
- **Diamond Proxy Architecture**: HyperStaking is built on the ERC-2535 standard, allowing modular and upgradeable contract functionality.
- **Staking Pools**: Supports staking pools, capable of integrating with various strategies.
- **Revenue Strategies**: Pools are linked to yield-generating strategies.
- **ERC4626 Integration**: Tier 2 utilizes the ERC4626 standard for vaults, ensuring compatibility with DeFi, where LP tokens represent the staked ETH and its associated revenue.
- **Revarding Fee Logic**: Introduces a fee system for Tier 1, calculated based on the revenue generated from the underlying asset (not the stake itself). Fees are distributed among LP token holders, enhancing the value of Tier 2 shares.
- **Hyperlane Integration**: Building a cross-chain bridge using Hyperlane for interaction between chains.

### Testing

Run the following to test contracts and check coverage:

```bash
npm run test                        # Runs all contract tests
REPORT_GAS=true npx hardhat test    # Runs tests with gas report
npm run coverage                    # Generates test coverage report
```

### Linting

Ensure code follows standards and is properly formatted using:

```bash
npm run prettier          # Formats Solidity files using Prettier
npm run lint              # Lints Solidity and JS/TS files for formatting issues
npm run check             # Runs Solhint to check Solidity code quality
```

### Documentation

Generate documentation for the contracts:

```bash
npm run docgen            # Generates contract documentation
```

### Deployment

The project is set up to deploy contracts using Hardhat Ignition. You can deploy the HyperStaking module by running e.g.:

```bash
npx hardhat ignition deploy ignition/modules/HyperStaking.ts --network holesky
```

Lumia Diamond:

```bash
npx hardhat ignition deploy ignition/modules/LumiaDiamond.ts --parameters ignition/parameters.holesky.json --network holesky
```

Check the `package.json` for deployment scripts related to strategies.

## Foundry Integration

The foundry-plugin has been added to this project to enhance testing and development, allowing for the integration of external tools and libraries, such as Solmate.
