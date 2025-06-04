# HyperStaking Contracts

This repository contains the HyperStaking contracts, built using Hardhat for testing, deployment, and development. The contracts utilize the Diamond Proxy architecture (ERC-2535).

## Project Overview

This project introduces multiple staking pools and a range of yield-generating strategies, allowing users to stake various tokens into different pools. The system is designed to easily accommodate new pools and strategies as needed.

### Key Features:
- **Diamond Proxy Architecture**: HyperStaking is built on the ERC-2535 standard, allowing modular and upgradeable contract functionality.
- **Staking Pools**: Supports staking pools, capable of integrating with various strategies.
- **ERC4626 Vaults**: Implements ERC-4626–compatible vaults on the Lumia-chain side, representing the staked asset on the origin chain together with generated revenue from the yield strategy.
- **Hyperlane Integration**: Building a cross-chain bridge using Hyperlane for interaction between chains.
- **Reward Distribution**: Introduces an inter-chain report system on the revenue generated from the underlying assets. Collected fees are distributed among shares token holders, boosting share value.

### Testing

Run the following to test contracts and check coverage:

```bash
# Run unit tests
npm run test:unit

# Run integration tests against a forked network
npm run test:fork

# Run tests with a gas report
REPORT_GAS=true npx hardhat test

# Generate a coverage report
npm run coverage
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
