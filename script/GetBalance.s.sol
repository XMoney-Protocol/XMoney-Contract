// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/XVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// forge script script/GetTokenBalance.s.sol --broadcast --rpc-url base_sepolia

contract GetBalance is Script {
    function run() external view {
        // Get configuration from environment variables
        address payable xVaultAddress = payable(vm.envAddress("XVAULT_ADDRESS"));
        
        // These parameters can also be passed through environment variables
        string memory username = 'testuser';
        address tokenAddress = vm.envAddress("TEST_TOKEN_ADDRESS");

        XVault vault = XVault(xVaultAddress);

        // Get native token balance
        uint256 nativeTokenBalance = vault.getNativeTokenBalance(username);
        console2.log("Native Token Balance for %s: %s", username, nativeTokenBalance);

        // Get token balance
        if (tokenAddress != address(0)) {
            uint256 tokenBalance = vault.getTokenBalance(username, tokenAddress);
            console2.log("Token Balance for %s at %s: %s", username, tokenAddress, tokenBalance);
        }
    }
} 