// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/XMoney.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BatchTransferToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable xMoneyAddress = payable(vm.envAddress("XMONEY_ADDRESS"));
        address tokenAddress = vm.envAddress("TEST_TOKEN_ADDRESS");
        
        // Generate 10 unregistered usernames and 10 registered addresses (example)
        string[] memory unregisteredUsernames = new string[](1000);
        uint256[] memory vaultAmounts = new uint256[](1000);  // Unregistered user amounts
        address[] memory registeredAddresses = new address[](10);
        uint256[] memory directAmounts = new uint256[](10);   // Registered user amounts
        
        // Initialize unregistered user data
        for(uint i = 0; i < 1000; i++) {
            unregisteredUsernames[i] = string(abi.encodePacked("unregistered", vm.toString(i + 1)));
            vaultAmounts[i] = 1 * 10**18; // Transfer 1 token per unregistered user
            console2.log("Unregistered user: %s", unregisteredUsernames[i]);
        }
        
        // Initialize registered user data
        for(uint i = 0; i < 10; i++) {
            registeredAddresses[i] = address(uint160(0x1000 + i));
            directAmounts[i] = 1 * 10**18; // Transfer 1 token per registered user
            console2.log("Registered address: %s", registeredAddresses[i]);
        }
        
        // Calculate total transfer amount
        uint256 totalAmount = 0;
        for(uint i = 0; i < vaultAmounts.length; i++) {
            totalAmount += vaultAmounts[i];
        }
        for(uint i = 0; i < directAmounts.length; i++) {
            totalAmount += directAmounts[i];
        }

        XMoney xMoney = XMoney(xMoneyAddress);
        IERC20 token = IERC20(tokenAddress);

        vm.startBroadcast(deployerPrivateKey);
        
        // Approve total amount
        token.approve(xMoneyAddress, totalAmount);
        // Execute batch transfer
        xMoney.batchTransferToken(
            unregisteredUsernames,
            vaultAmounts,
            registeredAddresses,
            directAmounts,
            tokenAddress
        );

        vm.stopBroadcast();

        console2.log("Batch token transfer completed");
        console2.log("Total amount transferred: %s", totalAmount);
        
        // Print transfer details example
        console2.log("\nUnregistered users transfer details (first 3):");
        for(uint i = 0; i < 3 && i < unregisteredUsernames.length; i++) {
            console2.log("Transfer %d: %s tokens to %s", 
                i + 1, 
                vaultAmounts[i], 
                unregisteredUsernames[i]
            );
        }
        
        console2.log("\nRegistered users transfer details (first 3):");
        for(uint i = 0; i < 3 && i < registeredAddresses.length; i++) {
            console2.log("Transfer %d: %s tokens to %s", 
                i + 1, 
                directAmounts[i], 
                registeredAddresses[i]
            );
        }
    }
} 