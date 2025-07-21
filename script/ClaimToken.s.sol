// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/XVault.sol";

contract ClaimToken is Script {
    function run() external {
        uint256 privateKey = vm.envUint("TEST_USER_PRIVATE_KEY");
        address payable xVaultAddress = payable(vm.envAddress("XVAULT_ADDRESS"));
        address tokenAddress = vm.envAddress("TEST_TOKEN_ADDRESS");
        
        XVault vault = XVault(xVaultAddress);
        
        vm.startBroadcast(privateKey);
        
        // User withdraws 50 tokens
        vault.withdrawToken("testuser", tokenAddress);
        
        vm.stopBroadcast();
        
        console2.log("Token claimed successfully");
    }
} 