# XMoney Protocol

XMoney is a revolutionary crypto payment protocol built on top of XID, enabling seamless transfers to 𝕏 users using only their handle — no wallet address required. Users can send BNB, stablecoins, and any BEP-20 token directly through social interactions.

## Key Capabilities

- **Handle-Based Transfers**: Send crypto to any 𝕏 user using just their @handle
- **Multi-Recipient Support**: Transfer to single users or batches of recipients
- **No Wallet Required**: Recipients don't need to know their wallet address
- **Secure Vault System**: Funds are safely stored until users claim them

By combining identity and onchain payments, XMoney unlocks a powerful new toolset for mass crypto adoption on 𝕏.

## Contract Addresses (BSC Mainnet)

- **XMoney Contract**: `0xaEd18172E5F0a5b303928b13890b3a01BDa1b143`
- **XVault Contract**: `0xBeeb32C59b70F2d41b5Fcf64e6A3Da777eB7317f`

## Links

- **XMoney DApp**: [XMoney](https://xmoney.to)
- **XID DApp**: [XID](https://xid.so)
- **XID Protocol**: [XID on GitHub](https://github.com/XIDProtocol)

## Features

- Transfer BNB and BEP-20 tokens using 𝕏 username
- Secure vault system for unclaimed funds
- Batch transfer support for multiple recipients
- Built with OpenZeppelin contracts for security
- Non-custodial design
- Reentrancy protection

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity ^0.8.24
- OpenZeppelin Contracts ^5.0.0

## Installation

1. Clone the repository:
```shell
git clone <your-repo-url>
cd XMoney-Contract
```

2. Install dependencies:
```shell
forge install
```

3. Copy environment variables:
```shell
cp .env.example .env
```

4. Configure your `.env` file with the required addresses and keys.

## Usage

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Deploy

Deploy the contracts to network:

```shell
forge script script/DeployContract.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

### Transfer Tokens

Send tokens to an XID username:

```shell
forge script script/TransferToken.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

### Batch Transfer

Send to multiple recipients:

```shell
forge script script/BatchTransferEth.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

### Check Balances

Query balances for an XID username:

```shell
forge script script/GetBalance.s.sol --rpc-url <your_rpc_url>
```

## Environment Variables

Create a `.env` file with the following variables:

```shell
# Private key for deployment (without 0x prefix)
PRIVATE_KEY=your_private_key_here

# Contract addresses
XID_ADDRESS=0x0000000000000000000000000000000000000000
FEE_RECEIVER=0x0000000000000000000000000000000000000000

# BSC MAINNET
XMONEY_ADDRESS=0x0000000000000000000000000000000000000000
XVAULT_ADDRESS=0x0000000000000000000000000000000000000000

# Test configuration
TEST_TOKEN_ADDRESS=0x0000000000000000000000000000000000000000
TEST_USER_PRIVATE_KEY=your_test_private_key_here
```

## Contract Architecture

The system consists of two main contracts:

1. **XMoney**: Handles the transfer logic and fee management
   - Supports BNB and BEP-20 token transfers
   - Implements reentrancy protection
   - Configurable fee system
   - Batch transfer capabilities
   
2. **XVault**: Manages unclaimed funds
   - Secure storage for unclaimed BNB and tokens
   - Balance tracking per username
   - Withdrawal mechanism for claimed funds
   - Fee calculation on withdrawals

## Security Features

- Uses OpenZeppelin's ReentrancyGuard
- Non-custodial design - funds are either transferred directly or held in XVault
- Configurable fee system with owner controls
- Event emission for all important operations
- Built on audited OpenZeppelin contracts
- SafeERC20 for secure token transfers


## Documentation

For detailed documentation about Foundry's capabilities, visit the [Foundry Book](https://book.getfoundry.sh/).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.