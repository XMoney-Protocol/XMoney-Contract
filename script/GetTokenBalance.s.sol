// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// forge script script/xmoney/GetTokenBalance.s.sol --broadcast --rpc-url base_sepolia

contract GetTokenBalance is Script {
    function run() external view {
        address tokenAddress = vm.envAddress("TEST_TOKEN_ADDRESS");
        IERC20Metadata token = IERC20Metadata(tokenAddress);

        // List of addresses to query
        address[] memory addresses = new address[](1);
        addresses[0] = 0xd015fE70Fd9010Fa727f756CE730975Dd6145F62; // Example address 1

        string memory symbol = token.symbol();
        uint8 decimals = token.decimals();

        console2.log("\nToken Address:", tokenAddress);
        console2.log("Symbol:", symbol);
        console2.log("Decimals:", decimals);
        console2.log("\n=== Token Balances ===");

        for (uint256 i = 0; i < addresses.length; i++) {
            uint256 balance = token.balanceOf(addresses[i]);
            console2.log("Address:", addresses[i]);
            console2.log("Balance:", balance / 10**decimals, symbol);
            console2.log("Raw Balance:", balance);
            console2.log("-------------------");
        }
    }
} 