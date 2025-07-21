// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/XMoney.sol";
import "../src/XVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract TransferToken is Script {
    function run() external {
        // Get configuration from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable xMoneyAddress = payable(vm.envAddress("XMONEY_ADDRESS"));
        
        // These parameters can also be passed through environment variables
        string memory username = 'testuser';
        address tokenAddress = vm.envAddress("TEST_TOKEN_ADDRESS");
        uint256 amount = 100 * 10**18; // Calculated in minimum units, e.g. 100 * 10**18

        vm.startBroadcast(deployerPrivateKey);

        IERC20 token = IERC20(tokenAddress);
        XMoney xMoney = XMoney(xMoneyAddress);
        // Check token balance
        uint256 balance = token.balanceOf(vm.addr(deployerPrivateKey));
        require(balance >= amount, "Insufficient token balance");

        // Transfer through XMoney
        token.approve(xMoneyAddress, amount);
        xMoney.transferToken(username, amount, tokenAddress);
        console.log("Transferred via XMoney:");

        vm.stopBroadcast();

        // Print transfer details
        console.log("- Token address:", tokenAddress);
        console.log("- Amount:", amount);
        console.log("- To username:", username);
        
    }
} 