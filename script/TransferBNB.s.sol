// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/XMoney.sol";

contract TransferNativeToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable xMoneyAddress = payable(vm.envAddress("XMONEY_ADDRESS"));
        
        string memory username = "testuser";
        uint256 amount = 0.00000005 ether;

        XMoney xMoney = XMoney(xMoneyAddress);

        vm.startBroadcast(deployerPrivateKey);
        
        xMoney.transferNativeToken{value: amount}(username);

        vm.stopBroadcast();

        console2.log("Transferred %s native token to %s", amount, username);
    }
} 