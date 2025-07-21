# X Transfer

A decentralized payment system built on [XID](https://github.com/XIDProtocol/XID) that enables transfers using 𝕏 username instead of address. Built with Foundry.

## Features

- Transfer ETH and ERC20 tokens using 𝕏 username
- Secure vault system for unclaimed funds
- Batch transfer support
- Built with OpenZeppelin contracts for security
- Non-custodial design
- Fee system with configurable rates
- Reentrancy protection

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity ^0.8.24
- OpenZeppelin Contracts ^5.0.0

## Installation

1. Clone the repository:
```shell
git clone <your-repo-url>
cd XTransfer
```

2. Install dependencies:
```shell
forge install
```

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

Deploy the contract to network:

```shell
forge script script/XTransfer.s.sol:XTransferScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Transfer Tokens

Send tokens to an XID username:

```shell
forge script script/TransferToken.s.sol:TransferToken --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Check Balances

Query balances for an XID username:

```shell
forge script script/GetBalance.s.sol:GetBalance --rpc-url <your_rpc_url>
```

## Environment Variables

Create a `.env` file with the following variables:

```shell
PRIVATE_KEY=your_private_key
XTRANSFER_ADDRESS=deployed_xtransfer_contract_address
XVAULT_ADDRESS=deployed_xvault_contract_address
TEST_TOKEN_ADDRESS=erc20_token_address
```

## Contract Architecture

The system consists of two main contracts:

1. **XTransfer**: Handles the transfer logic and fee management
   - Supports ETH and ERC20 token transfers
   - Implements reentrancy protection
   - Configurable fee system
   - Batch transfer capabilities

2. **XVault**: Manages unclaimed funds
   - Secure storage for unclaimed ETH and tokens
   - Balance tracking per username
   - Withdrawal mechanism for claimed funds

## Security Features

- Uses OpenZeppelin's ReentrancyGuard
- Non-custodial design - funds are either transferred directly or held in XVault
- Configurable fee system with owner controls
- Event emission for all important operations
- Built on audited OpenZeppelin contracts

## Documentation

For detailed documentation about Foundry's capabilities, visit the [Foundry Book](https://book.getfoundry.sh/).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.

# XTransfer 费用分配器

这个项目实现了一个费用分配系统，允许XTransfer合约的费用按照固定比例分配给两个控制者。

## 合约结构

- **XTransfer.sol**: 主要的转账合约，支持基于XID的ETH和ERC20代币转账
- **FeeDistributor.sol**: 费用分配合约，作为XTransfer的feeReceiver，将收到的费用按照10%/90%的比例分配给两个控制者

## 费用分配机制

1. XTransfer合约收取的所有费用都会累积在XTransfer合约中
2. FeeDistributor合约可以调用XTransfer合约的claim函数领取累积的费用
3. 控制者1可以随时调用FeeDistributor合约领取10%的费用
4. 控制者2可以随时调用FeeDistributor合约领取90%的费用
5. 每个控制者只能领取自己的份额

## 部署步骤

1. 部署FeeDistributor合约，指定两个控制者地址和XTransfer合约地址
2. 将FeeDistributor合约地址设置为XTransfer合约的feeReceiver

使用Foundry部署脚本:

```bash
# 设置环境变量
export PRIVATE_KEY=你的私钥
export CONTROLLER1_ADDRESS=控制者1地址
export CONTROLLER2_ADDRESS=控制者2地址
export XTRANSFER_ADDRESS=XTransfer合约地址

# 部署合约
forge script script/DeployFeeDistributor.s.sol --rpc-url <你的RPC URL> --broadcast
```

## 使用方法

### 从XTransfer合约领取费用

控制者或合约所有者可以调用以下函数从XTransfer合约领取累积的费用:

```solidity
// 领取ETH费用
feeDistributor.claimNativeTokenFeesFromXTransfer()

// 领取特定代币费用
feeDistributor.claimTokenFeesFromXTransfer(tokenAddress)

// 领取多个代币费用
feeDistributor.claimMultipleTokenFeesFromXTransfer(tokenAddresses)
```

### 从FeeDistributor合约领取费用

控制者可以调用以下函数从FeeDistributor合约领取自己的份额:

```solidity
// 领取ETH费用
feeDistributor.claimNativeTokenFees()

// 领取代币费用
feeDistributor.claimTokenFees(tokenAddress)
```

### 更新控制者

合约所有者可以更新控制者地址:

```solidity
feeDistributor.setController(controllerIndex, newControllerAddress)
```

其中`controllerIndex`为1或2，分别代表10%和90%的控制者。

### 更新XTransfer地址

合约所有者可以更新XTransfer合约地址:

```solidity
feeDistributor.setXTransfer(newXTransferAddress)
```

## 测试

运行测试:

```bash
forge test -vv
```

测试包括:
- ETH费用分配测试
- 代币费用分配测试
- 多代币费用分配测试
- 控制者更新测试
- XTransfer更新测试
- 权限控制测试