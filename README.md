# Hop Messenger

The Hop Messenger is a modular, trustless messaging protocol that can be used to build powerful cross-chain applications.

## Contracts

The Hop Messenger includes the following contracts:
 * `Dispatcher`s - dispatch and bundle messages
 * `Executor`s - validate and execute messages
 * `Transporter`s - connect cross-chain Dispatchers and Executors
 * `Connector`s - Easy one-to-one cross-chain connections
 * `Alias`es - Control a cross-chain Alias contract with any contract

### Dispatchers

There is a single `Dispatcher` on each chain. Dispatchers are responsible for aggregating messages into bundles sending the bundle to the destination through the transport layer. A small fee is required for each message that is dispatched which goes toward the cost of transporting the bundle. 

### Executors

`Executor`s are responsible for validating and executing messages. There is one `Executor` deployed on every supported chain. Before a message can be executed, the `Executor` must prove the bundle by verifying it with the `Transporter`.

### Transporters

See [Transporter package](https://github.com/hop-protocol/contracts-v2/packages/transporter).

A `Transporter` is used by the messenger for tranporting data such as bundles cross-chain. The data being transported is always represented by a single hash called a `commitment`. In this case, the `commitment` is the hash of the bundle data -- the `bundleHash`.

The `Transporter` uses the cannonical bridges to transport the `bundleHash` using Ethereum as a hub. This is a simple transport method optimized for trustlessness and security but it can be quite slow in some cases such as sending a message from an optimistic rollup.

## Getting Started

### Send a message

You can send a message by calling the EIP-5164 method, `dispatchMessage`.

```solidity
IMessageDispatcher(dispatcher).dispatchMessage(toChainId, to, data);
```

### Receive a message

When receiving a message, inherit from [`MessageReceiver`](https://github.com/hop-protocol/contracts-v2/blob/master/packages/messenger/contracts/ERC5164/MessageReceiver.sol) to access the `EIP-5164` validation data -- `messageId`, `from` address, and `fromChainId`.

```solidity
contract MyContract is MessageReceiver {
    event MyMessageHandleEvent {
        bytes32 indexed messageId /*,
        ... your event params*/
    }

    function myFunction() external {
        // Parse the cross-chain context from the call
        (bytes32 messageId, address from, uint256 fromChainId) = _crossChainContext();

        // Validate the cross-chain caller
        require(msg.sender == hopMessageBridge, "Invalid sender");
        require(from == expectedCrossChainSender, "Invalid cross-chain sender");
        require(fromChainId == expectedCrossChainId, "Invalid cross-chain chainId");

        // Execute your business logic
        emit MyMessageHandleEvent(messageId, /* your event params */);
    }
}
```

## Usage

### Compile Contracts
```shell
npm run compile
```

### Test
```shell
npm run test
```

### Deploy
Deploy to testnet chains (Goerli, Optimism Goerli, etc.)
```shell
npm run testnet:deploy
```

Deploy to mainnet chains (Ethereum, Arbitrum, etc.)
```shell
npm run mainnet
```

### Lint

```shell
npm run lint
```

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

### Run Tests

```
npm run test
```
