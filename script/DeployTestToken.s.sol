// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


// forge script script/DeployTestToken.s.sol --broadcast --rpc-url customNetwork


contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract DeployTestToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy test token
        TestToken token = new TestToken();

        vm.stopBroadcast();

        console.log("Test Token deployed at:", address(token));
        console.log("Total supply:", token.totalSupply() / 1e18, "TEST");
    }
} 