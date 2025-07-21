// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/XMoney.sol";
import "../src/XVault.sol";
import "forge-std/console2.sol";

contract DeployContract is Script {
    function run() external {
        // Get deployer private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeReceiver = vm.envAddress("FEE_RECEIVER");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy XVault contract first
        XVault xvault = new XVault(
            vm.envAddress("XID_ADDRESS"),  // XID contract address
            feeReceiver                    // Fee receiver address
        );
        console2.log("XVault deployed to:", address(xvault));

        // Then deploy XMoney contract with vault address
        XMoney xMoney = new XMoney(
            vm.envAddress("XID_ADDRESS"),  // XID contract address
            address(xvault),                // Set correct vault address directly
            feeReceiver
        );
        console2.log("XMoney deployed to:", address(xMoney));

        vm.stopBroadcast();
        
        console2.log("\nPlease add the following to your .env file:");
        console2.log("XMONEY_ADDRESS=", address(xMoney));
        console2.log("XVAULT_ADDRESS=", address(xvault));
    }
}