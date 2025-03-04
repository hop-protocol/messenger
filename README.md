# Hop Messenger

A monorepo for the smart contracts that power the Hop Messenger.

## Packages
 * [`messenger`](./packages/messenger) - A trustless messaging protocol for cross-chain applications
 * [`transporter`](./packages/transporter) - A transport implementation leveraging native bridges
 * [`connectors`](./packages/connectors) - Easy one-to-one cross-chain connections
 * [`aliases`](./packages/aliases) - Control a cross-chain Alias contract with any contract

The Hop Messenger is a modular messaging protocol that can be used to build powerful cross-chain applications.

## Testing

First, create an `.env` file based on `.env-sample` and [install Foundry](https://book.getfoundry.sh/getting-started/installation).

### Using Anvil

Optionally, you can spin up local networks using [`anvil`](https://book.getfoundry.sh/anvil/) instead of using external RPCs in your `.env` file.

```
anvil -p 8545 --chain-id 11155111
anvil -p 8546 --chain-id 11155420
anvil -p 8547 --chain-id 84532
anvil -p 8548 --chain-id 42069
```

`.env`
```
RPC_ENDPOINT_SEPOLIA="http://127.0.0.1:8545"
RPC_ENDPOINT_OPTIMISM_SEPOLIA="http://127.0.0.1:8546"
RPC_ENDPOINT_BASE_SEPOLIA="http://127.0.0.1:8547"
RPC_ENDPOINT_HOP_SEPOLIA="http://127.0.0.1:8548"
```

### Run Unit Tests

```
npm run test
```

### Run Single-Path Simulation

```
npm run test-single-path-simulation
```

### Run Hub Simulation

```
npm run test-multi-path-simulation
```

