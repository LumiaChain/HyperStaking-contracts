# HyperStaking Contracts

This repository contains the HyperStaking contracts, built using Hardhat for testing, deployment, and development. The contracts utilize the Diamond Proxy architecture (ERC-2535).

## Project Overview

This project introduces multiple staking pools and a range of yield-generating strategies, allowing users to stake various tokens into different pools, each potentially linked to multiple strategies. The system is designed to easily accommodate new pools and strategies as needed.

### Key Features:
- **Diamond Proxy Architecture**: HyperStaking is built on the ERC-2535 standard, allowing modular and upgradeable contract functionality.
- **Staking Pools**: Supports multiple staking pools, each capable of integrating with various strategies.
- **Revenue Strategies**: Pools can be linked to multiple yield-generating strategies.
Yield generation strategies for staked tokens.
- **Multi-Token Rewards**: Supports distributing multiple rewards per strategy, based on user contribution.

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
npm run lint_sol          # Checks Solidity files for formatting issues
npm run lint_js           # Lints JS and TS files using ESLint
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

## Foundry Integration

The foundry-plugin has been added to this project to enhance testing and development, allowing for the integration of external tools and libraries, such as Solmate, to streamline the development process.
