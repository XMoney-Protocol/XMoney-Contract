// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/XMoney.sol";
import "../src/interfaces/IXID.sol";

contract BatchTransferNativeToken is Script {
    function run() external {
        // Move variable declarations closer to usage to reduce stack depth
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable xMoneyAddress = payable(vm.envAddress("XMONEY_ADDRESS"));
        
        // Initialize contract
        XMoney xMoney = XMoney(xMoneyAddress);
        
        // Prepare transfer data
        (
            string[] memory unregisteredUsernames,
            uint256[] memory vaultAmounts,
            address[] memory registeredAddresses,
            uint256[] memory directAmounts,
            uint256 totalAmount
        ) = prepareTransferData();

        // Execute transfer
        vm.startBroadcast(deployerPrivateKey);
        
        xMoney.batchTransferNativeToken{value: totalAmount}(
            unregisteredUsernames,
            vaultAmounts,
            registeredAddresses,
            directAmounts
        );

        vm.stopBroadcast();

        console2.log("Batch transfer completed");
        console2.log("Total amount: %s", totalAmount);
    }

    // Separate data preparation logic into independent function to reduce main function stack depth
    function prepareTransferData() internal view returns (
        string[] memory unregisteredUsernames,
        uint256[] memory vaultAmounts,
        address[] memory registeredAddresses,
        uint256[] memory directAmounts,
        uint256 totalAmount
    ) {
        address xidAddress = vm.envAddress("XID_ADDRESS");
        IXID xid = IXID(xidAddress);
        
        // Prepare username list
        string[] memory allUsernames = new string[](4);
        allUsernames[0] = "elonmusk";
        allUsernames[1] = "testuser";
        allUsernames[2] = "0xAA_Science";
        allUsernames[3] = "0xtankxu";
        
        // Separate registered and unregistered users
        uint256 registeredCount = 0;
        uint256 unregisteredCount = 0;
        
        // First calculate the number of registered and unregistered users
        for(uint i = 0; i < allUsernames.length; i++) {
            try xid.getAddressByUsername(allUsernames[i]) returns (address) {
                registeredCount++;
            } catch {
                unregisteredCount++;
            }
        }
        
        // Create return arrays
        unregisteredUsernames = new string[](unregisteredCount);
        vaultAmounts = new uint256[](unregisteredCount);
        registeredAddresses = new address[](registeredCount);
        directAmounts = new uint256[](registeredCount);
        
        // Fill arrays
        uint256 unregisteredIndex = 0;
        uint256 registeredIndex = 0;
        totalAmount = 0;
        
        for(uint i = 0; i < allUsernames.length; i++) {
            try xid.getAddressByUsername(allUsernames[i]) returns (address userAddress) {
                registeredAddresses[registeredIndex] = userAddress;
                directAmounts[registeredIndex] = 0.00000001 ether;
                totalAmount += 0.00000001 ether;
                console2.log("Registered user: %s at %s", allUsernames[i], userAddress);
                registeredIndex++;
            } catch {
                unregisteredUsernames[unregisteredIndex] = allUsernames[i];
                vaultAmounts[unregisteredIndex] = 0.00000001 ether;
                totalAmount += 0.00000001 ether;
                console2.log("Unregistered user: %s", allUsernames[i]);
                unregisteredIndex++;
            }
        }
    }
} 