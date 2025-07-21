// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/FeeDistributor.sol";
import "../src/XMoney.sol";

contract DeployFeeDistributor is Script {
    function run() external {
        // Get private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address controller1 = vm.envAddress("CONTROLLER1_ADDRESS");
        address controller2 = vm.envAddress("CONTROLLER2_ADDRESS");
        address xMoneyAddress = vm.envAddress("XMONEY_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy FeeDistributor contract with XMoney address
        FeeDistributor feeDistributor = new FeeDistributor(
            controller1, 
            controller2,
            xMoneyAddress
        );
        
        // Set FeeDistributor as XMoney's feeReceiver
        XMoney(payable(xMoneyAddress)).setFeeReceiver(address(feeDistributor));
        
        vm.stopBroadcast();
        
        // Output deployment information
        console.log("FeeDistributor deployed at:", address(feeDistributor));
        console.log("Controller1 (10%):", controller1);
        console.log("Controller2 (90%):", controller2);
        console.log("XMoney:", xMoneyAddress);
        console.log("XMoney feeReceiver updated to FeeDistributor");
    }
} 