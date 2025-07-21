// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/XMoney.sol";
import "../src/XVault.sol";
import "../src/interfaces/IXVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// TODO: 测试转账事件触发

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock XID contract for testing
contract MockXID {
    address public controller;
    mapping(address => string) private _addressToUsername;
    mapping(string => address) private _usernameToAddress;

    function setController(address _controller) external {
        controller = _controller;
    }

    function mint(address user, string memory username, uint256) external {
        require(msg.sender == controller, "Not controller");
        require(user != address(0), "Invalid user address");

        // Clear old mappings if they exist
        if (bytes(_addressToUsername[user]).length > 0) {
            delete _usernameToAddress[_addressToUsername[user]];
        }
        if (_usernameToAddress[username] != address(0)) {
            delete _addressToUsername[_usernameToAddress[username]];
        }

        _addressToUsername[user] = username;
        _usernameToAddress[username] = user;
    }

    function getAddressByUsername(
        string memory username
    ) external view returns (address) {
        return _usernameToAddress[username];
    }

    function getUsernameByAddress(
        address user
    ) external view returns (string memory) {
        return _addressToUsername[user];
    }
}

contract XMoneyTest is Test {
    XMoney public xMoney;
    XVault public xVault;
    MockXID public xid;
    MockToken public mockToken;

    event NativeTokenTransferred(
        address indexed from,
        string indexed toUsername,
        uint256 amount,
        uint256 fee
    );

    event BatchNativeTokenTransferred(
        address indexed from,
        string[] toUsernames,
        address[] toAddresses,
        uint256 totalVaultAmount,
        uint256 totalDirectAmount,
        uint256 totalFee
    );

    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    event FeeReceiverUpdated(address oldReceiver, address newReceiver);
    event XidAddressUpdated(address oldXid, address newXid);
    event XVaultAddressUpdated(address oldVault, address newVault);

    address public deployer;
    address public user1;
    address public user2;
    address public mockController;
    address public feeReceiver;

    uint256 constant FEE_RATE = 100; // 1% (基数为10000)

    function _usernameHash(
        string memory username
    ) internal pure returns (bytes32) {
        return keccak256(bytes(username));
    }

    function setUp() public {
        deployer = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        mockController = makeAddr("mockController");
        feeReceiver = makeAddr("feeReceiver");

        xid = new MockXID();
        xid.setController(mockController);
        xVault = new XVault(address(xid), feeReceiver);
        xMoney = new XMoney(address(xid), address(xVault), feeReceiver);
        mockToken = new MockToken();

        // Transfer ownership of xVault to deployer (test contract)
        xVault.transferOwnership(deployer);

        // Fund accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        mockToken.transfer(user1, 1000 * 10 ** 18);
        mockToken.transfer(user2, 1000 * 10 ** 18);
    }

    function testTransferNativeTokenToRegisteredUser() public {
        string memory username = "user1";
        uint256 amount = 1 ether;
        uint256 expectedFee = (amount * FEE_RATE) / 10000;
        uint256 expectedTransfer = amount - expectedFee;

        // Register user1 with XID
        vm.prank(mockController);
        xid.mint(user1, username, 1);

        // 记录初始余额
        uint256 initialBalance = user1.balance;

        // Transfer native token and expect event
        vm.prank(user2);
        vm.expectEmit(true, true, false, true);
        emit NativeTokenTransferred(user2, username, expectedTransfer, expectedFee);
        xMoney.transferNativeToken{value: amount}(username);

        // 验证余额变化
        assertEq(user1.balance - initialBalance, expectedTransfer);
        assertEq(xMoney.getAccumulatedNativeTokenFees(), expectedFee);
    }

    function testTransferNativeTokenToUnregisteredUser() public {
        string memory username = "unregistered";
        uint256 amount = 1 ether;

        vm.prank(user1);
        xMoney.transferNativeToken{value: amount}(username);

        console.log("xVault.getNativeTokenBalance(username)", xVault.getNativeTokenBalance(username));

        assertEq(xVault.getNativeTokenBalance(username), amount);
    }

    function testTransferTokenToRegisteredUser() public {
        string memory username = "user1";
        uint256 amount = 100 * 10 ** 18;
        uint256 expectedFee = (amount * FEE_RATE) / 10000;
        uint256 expectedTransfer = amount - expectedFee;

        // Initial balance is 1000 * 10**18 from setUp()
        uint256 initialBalance = 1000 * 10 ** 18;

        // Register user1 with XID
        vm.prank(mockController);
        xid.mint(user1, username, 1);

        // Approve and transfer tokens
        vm.startPrank(user2);
        mockToken.approve(address(xMoney), amount);
        xMoney.transferToken(username, amount, address(mockToken));
        vm.stopPrank();

        // Updated assertion to account for initial balance + transfer amount - fee
        assertEq(mockToken.balanceOf(user1), initialBalance + expectedTransfer);
    }

    function testTransferTokenToUnregisteredUser() public {
        string memory username = "unregistered";
        uint256 amount = 120 * 10 ** 18;

        vm.startPrank(user1);
        mockToken.approve(address(xMoney), amount);
        xMoney.transferToken(username, amount, address(mockToken));
        vm.stopPrank();
        
        console.log("xVault.getTokenBalance(username, address(mockToken))", xVault.getTokenBalance(username, address(mockToken)));
        assertEq(xVault.getTokenBalance(username, address(mockToken)), amount);
    }

    function testBatchTransferNativeToken() public {
        // Reset balances before test
        vm.deal(user1, 0);
        vm.deal(user2, 100 ether);
        vm.deal(feeReceiver, 0);

        // 准备未注册用户数据
        string[] memory unregisteredUsernames = new string[](1);
        unregisteredUsernames[0] = "unregistered";
        uint256[] memory vaultAmounts = new uint256[](1);
        vaultAmounts[0] = 2 ether;

        // 准备已注册用户数据
        address[] memory registeredAddresses = new address[](1);
        registeredAddresses[0] = user1;
        uint256[] memory directAmounts = new uint256[](1);
        directAmounts[0] = 1 ether;

        // 注册用户1
        vm.prank(mockController);
        xid.mint(user1, "user1", 1);

        // 计算预期的手续费和实际转账金额
        uint256 expectedFee = (directAmounts[0] * FEE_RATE) / 10000;
        uint256 expectedTransfer = directAmounts[0] - expectedFee;

        vm.prank(user2);
        xMoney.batchTransferNativeToken{value: 3 ether}(
            unregisteredUsernames,
            vaultAmounts,
            registeredAddresses,
            directAmounts
        );

        // 验证已注册用户收到的金额（扣除1%手续费）
        assertEq(user1.balance, expectedTransfer);
        // 验证未注册用户的金额存入金库（不收手续费）
        assertEq(xVault.getNativeTokenBalance("unregistered"), 2 ether);
        // 验证手续费接收者收到手续费
        assertEq(xMoney.getAccumulatedNativeTokenFees(), expectedFee);
    }

    function testBatchTransferToken() public {
        // 准备未注册用户数据
        string[] memory unregisteredUsernames = new string[](1);
        unregisteredUsernames[0] = "unregistered";
        uint256[] memory vaultAmounts = new uint256[](1);
        vaultAmounts[0] = 200 * 10 ** 18;

        // 准备已注册用户数据
        address[] memory registeredAddresses = new address[](1);
        registeredAddresses[0] = user1;
        uint256[] memory directAmounts = new uint256[](1);
        directAmounts[0] = 100 * 10 ** 18;

        // 注册用户1
        vm.prank(mockController);
        xid.mint(user1, "user1", 1);

        // Initial balance is 1000 * 10**18 from setUp()
        uint256 initialBalance = 1000 * 10 ** 18;
        uint256 expectedFee = (directAmounts[0] * FEE_RATE) / 10000;
        uint256 expectedTransfer = directAmounts[0] - expectedFee;

        // 执行批量转账
        vm.startPrank(user2);
        mockToken.approve(address(xMoney), 300 * 10 ** 18);
        xMoney.batchTransferToken(
            unregisteredUsernames,
            vaultAmounts,
            registeredAddresses,
            directAmounts,
            address(mockToken)
        );
        vm.stopPrank();

        // 验证已注册用户收到的金额（扣除1%手续费）
        assertEq(mockToken.balanceOf(user1), initialBalance + expectedTransfer); // initial 1000 + (100 - 1% fee)
        // 验证未注册用户的金额存入金库（不收手续费）
        assertEq(
            xVault.getTokenBalance("unregistered", address(mockToken)),
            vaultAmounts[0]
        );
        // 验证手续费接收者收到手续费
        assertEq(xMoney.getAccumulatedTokenFees(address(mockToken)), expectedFee);
    }

    function testWithdrawUnauthorized() public {
        string memory username = "user1";
        uint256 amount = 1 ether;

        // Register user1 with XID
        vm.prank(mockController);
        xid.mint(user1, username, 1);

        // Deposit ETH to vault
        vm.prank(user1);
        xMoney.transferNativeToken{value: amount}(username);

        // Try to withdraw using unauthorized address (user2)
        vm.prank(user2);
        vm.expectRevert("XVault: Caller is not the XID owner");
        xVault.withdrawNativeToken(username);
    }

    function testWithdrawEmptyBalance() public {
        string memory username = "user1";

        // Register user1 with XID
        vm.prank(mockController);
        xid.mint(user1, username, 1);

        // Try to withdraw with no balance
        vm.prank(user1);
        vm.expectRevert("XVault: No native token balance");
        xVault.withdrawNativeToken(username);
    }

    function testBatchTransferNativeTokenGasEstimate() public {
        // Prepare 20 usernames and addresses (10 registered, 10 unregistered)
        string[] memory unregisteredUsernames = new string[](10);
        uint256[] memory vaultAmounts = new uint256[](10);
        address[] memory registeredAddresses = new address[](10);
        uint256[] memory directAmounts = new uint256[](10);
        uint256 totalAmount = 0;

        // Initialize data
        for (uint i = 0; i < 10; i++) {
            // Unregistered user
            unregisteredUsernames[i] = string(
                abi.encodePacked("unregistered", vm.toString(i))
            );
            vaultAmounts[i] = 0.001 ether;

            // Registered user
            string memory registeredUsername = string(
                abi.encodePacked("registered", vm.toString(i))
            );
            address user = makeAddr(registeredUsername);
            registeredAddresses[i] = user;
            directAmounts[i] = 0.001 ether;

            // Register XID for registered user
            vm.prank(mockController);
            xid.mint(user, registeredUsername, 1);

            totalAmount += 0.002 ether; // Total 0.002 ether per user pair
        }

        // Ensure sender has sufficient ETH
        vm.deal(user1, totalAmount + 1 ether);

        // Execute batch transfer and measure gas
        vm.prank(user1);
        uint256 gasBefore = gasleft();
        xMoney.batchTransferNativeToken{value: totalAmount}(
            unregisteredUsernames,
            vaultAmounts,
            registeredAddresses,
            directAmounts
        );
        uint256 gasUsed = gasBefore - gasleft();

        // Verify transfer results
        for (uint i = 0; i < 10; i++) {
            // Verify unregistered user funds entered vault
            assertEq(
                xVault.getNativeTokenBalance(unregisteredUsernames[i]),
                0.001 ether
            );
            // Verify registered user received funds (minus 1% fee)
            assertEq(registeredAddresses[i].balance, 0.00099 ether); // 0.001 ether - 1% fee
        }

        console.log("Gas used for 20 transfers:", gasUsed);
    }

    function testBatchTransferTokenGasEstimate() public {
        // Prepare 20 usernames and addresses (10 registered, 10 unregistered)
        string[] memory unregisteredUsernames = new string[](10);
        uint256[] memory vaultAmounts = new uint256[](10);
        address[] memory registeredAddresses = new address[](10);
        uint256[] memory directAmounts = new uint256[](10);
        uint256 totalAmount = 0;

        // Initialize data
        for (uint i = 0; i < 10; i++) {
            // Unregistered user
            unregisteredUsernames[i] = string(
                abi.encodePacked("unregistered", vm.toString(i))
            );
            vaultAmounts[i] = 1000 * 10 ** 18; // 1000 tokens

            // Registered user
            string memory registeredUsername = string(
                abi.encodePacked("registered", vm.toString(i))
            );
            address user = makeAddr(registeredUsername);
            registeredAddresses[i] = user;
            directAmounts[i] = 1000 * 10 ** 18; // 1000 tokens

            // Register XID for registered user
            vm.prank(mockController);
            xid.mint(user, registeredUsername, 1);

            totalAmount += 2000 * 10 ** 18; // Total 2000 tokens per user pair
        }

        // Ensure sender has sufficient tokens
        mockToken.mint(user1, totalAmount + 1000 * 10 ** 18);

        // Approve transfer
        vm.startPrank(user1);
        mockToken.approve(address(xMoney), totalAmount);

        // Execute batch transfer and measure gas
        uint256 gasBefore = gasleft();
        xMoney.batchTransferToken(
            unregisteredUsernames,
            vaultAmounts,
            registeredAddresses,
            directAmounts,
            address(mockToken)
        );
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        // Verify transfer results
        for (uint i = 0; i < 10; i++) {
            // Verify unregistered user tokens entered vault
            assertEq(
                xVault.getTokenBalance(
                    unregisteredUsernames[i],
                    address(mockToken)
                ),
                1000 * 10 ** 18
            );
            // Verify registered user received tokens (minus 1% fee)
            assertEq(
                mockToken.balanceOf(registeredAddresses[i]),
                990 * 10 ** 18 // 1000 tokens - 1% fee
            );
        }

        console.log("Gas used for 20 token transfers:", gasUsed);
    }

    // Test transfer and withdrawal scenario
    function testTransferAndClaimScenario() public {
        // Reset all balances
        vm.deal(user1, 100 ether);
        vm.deal(feeReceiver, 0);

        // Set up initial scenario
        string[] memory unregisteredUsernames = new string[](3);
        unregisteredUsernames[0] = "elonmusk";
        unregisteredUsernames[1] = "jack";
        unregisteredUsernames[2] = "donald";

        // Transfer amounts for unregistered users
        uint256[] memory vaultAmounts = new uint256[](3);
        vaultAmounts[0] = 20 ether;
        vaultAmounts[1] = 20 ether;
        vaultAmounts[2] = 20 ether;

        // Registered user setup
        address[] memory registeredAddresses = new address[](1);
        address testuser = makeAddr("testuser");
        registeredAddresses[0] = testuser;
        vm.deal(testuser, 0); // Reset testuser's balance

        // Transfer amounts for registered users
        uint256[] memory directAmounts = new uint256[](1);
        directAmounts[0] = 20 ether;

        // Register XID for testuser
        vm.prank(mockController);
        xid.mint(testuser, "testuser", 1);

        // Set elon's address for later use
        address elon = makeAddr("elonmusk");
        vm.deal(elon, 0); // Reset elon's balance

        // Execute batch transfer
        vm.prank(user1);
        xMoney.batchTransferNativeToken{value: 80 ether}(
            unregisteredUsernames,
            vaultAmounts,
            registeredAddresses,
            directAmounts
        );

        // Verify testuser received ETH directly (minus 1% fee)
        uint256 expectedDirectTransfer = (20 ether * (10000 - FEE_RATE)) /
            10000;
        uint256 expectedDirectFee = (20 ether * FEE_RATE) / 10000;
        assertEq(testuser.balance, expectedDirectTransfer);

        // Verify other users' ETH went into vault (no fee)
        assertEq(xVault.getNativeTokenBalance("elonmusk"), 20 ether);
        assertEq(xVault.getNativeTokenBalance("jack"), 20 ether);
        assertEq(xVault.getNativeTokenBalance("donald"), 20 ether);

        // Elon attempts to withdraw but fails (not registered)
        vm.prank(elon);
        vm.expectRevert("XVault: caller is not the XID owner");
        xVault.withdrawAll("elonmusk", new address[](0));

        // Elon registers XID
        vm.prank(mockController);
        xid.mint(elon, "elonmusk", 1);

        // Record elon's balance before withdrawal
        uint256 elonBalanceBefore = elon.balance;

        // elon can now successfully withdraw
        vm.prank(elon);
        address[] memory tokens = new address[](0);
        xVault.withdrawAll("elonmusk", tokens);

        // Calculate expected amount (10% fee charged for vault withdrawal)
        uint256 expectedAmount = (20 ether * (10000 - 1000)) / 10000;

        // Verify elon received correct amount (18 ETH, minus 10% fee)
        assertEq(elon.balance - elonBalanceBefore, expectedAmount);

        // Verify elon's vault balance is cleared
        assertEq(xVault.getNativeTokenBalance("elonmusk"), 0);

        assertEq(xMoney.getAccumulatedNativeTokenFees(), expectedDirectFee);
    }

    // Add new test for fee receiver functionality
    function testSetFeeReceiver() public {
        address newFeeReceiver = makeAddr("newFeeReceiver");

        // Only owner can set fee receiver
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        xMoney.setFeeReceiver(newFeeReceiver);

        // Owner can set fee receiver
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true, address(xMoney));
        emit FeeReceiverUpdated(feeReceiver, newFeeReceiver);
        xMoney.setFeeReceiver(newFeeReceiver);
        assertEq(xMoney.feeReceiver(), newFeeReceiver);
    }

    // Update test for balance checking
    function testGetBalances() public {
        string memory username = "test_user";

        // Setup initial balances
        vm.deal(address(this), 5 ether);
        xMoney.transferNativeToken{value: 1 ether}(username);

        mockToken.approve(address(xMoney), 100 * 10 ** 18);
        xMoney.transferToken(username, 100 * 10 ** 18, address(mockToken));

        // Verify ETH balance
        uint256 nativeTokenBalance = xVault.getNativeTokenBalance(username);
        assertEq(nativeTokenBalance, 1 ether);

        // Verify token balance
        uint256 tokenBalance = xVault.getTokenBalance(
            username,
            address(mockToken)
        );
        assertEq(tokenBalance, 100 * 10 ** 18);
    }

    // Add zero value transfer tests
    function testZeroValueTransfers() public {
        string memory username = "user1";

        // Test zero value ETH transfer
        vm.prank(user1);
        vm.expectRevert("XMoney: Amount must be greater than 0");
        xMoney.transferNativeToken{value: 0}(username);

        // Test zero token transfer
        vm.prank(user1);
        vm.expectRevert("XMoney: Amount must be greater than 0");
        xMoney.transferToken(username, 0, address(mockToken));
    }

    // Add batch transfer boundary condition tests
    function testBatchTransferValidation() public {
        string[] memory emptyUsernames = new string[](0);
        uint256[] memory emptyAmounts = new uint256[](0);
        address[] memory emptyAddresses = new address[](0);

        // Test empty arrays
        vm.prank(user1);
        vm.expectRevert("XMoney: Empty arrays");
        xMoney.batchTransferNativeToken(
            emptyUsernames,
            emptyAmounts,
            emptyAddresses,
            emptyAmounts
        );

        // Test array length mismatch
        string[] memory usernames = new string[](2);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(user1);
        vm.expectRevert("XMoney: Vault arrays length mismatch");
        xMoney.batchTransferNativeToken(
            usernames,
            amounts,
            emptyAddresses,
            emptyAmounts
        );
    }

    // Add admin function tests
    function testAdminFunctions() public {
        // Test setting new fee rate
        uint256 oldFeeRate = xMoney.feeRate();
        uint256 newFeeRate = 200; // 2%

        vm.prank(deployer);
        vm.expectEmit(true, true, true, true, address(xMoney));
        emit FeeRateUpdated(oldFeeRate, newFeeRate);
        xMoney.setFeeRate(newFeeRate);
        assertEq(xMoney.feeRate(), newFeeRate);

        // Test setting new fee receiver address
        address oldFeeReceiver = xMoney.feeReceiver();
        address newFeeReceiver = makeAddr("newFeeReceiver");

        vm.prank(deployer);
        vm.expectEmit(true, true, true, true, address(xMoney));
        emit FeeReceiverUpdated(oldFeeReceiver, newFeeReceiver);
        xMoney.setFeeReceiver(newFeeReceiver);
        assertEq(xMoney.feeReceiver(), newFeeReceiver);

        // Test non-admin call
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        xMoney.setFeeRate(300);
    }

    function testSetXidAddress() public {
        address oldXid = address(xid);
        address newXid = makeAddr("newXid");

        vm.prank(deployer);
        vm.expectEmit(true, true, true, true, address(xMoney));
        emit XidAddressUpdated(oldXid, newXid);
        xMoney.setXidAddress(newXid);

        assertEq(address(xMoney.xid()), newXid);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        xMoney.setXidAddress(newXid);
    }

    function testSetXVaultAddress() public {
        address oldVault = address(xVault);
        address newVault = makeAddr("newVault");

        vm.prank(deployer);
        vm.expectEmit(true, true, true, true, address(xMoney));
        emit XVaultAddressUpdated(oldVault, newVault);
        xMoney.setXVaultAddress(newVault);

        assertEq(address(xMoney.vault()), newVault);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        xMoney.setXVaultAddress(newVault);
    }

    function testClaimTokenFees() public {
        string memory username = "user1";
        uint256 amount = 100 * 10 ** 18;

        // Register user
        vm.prank(mockController);
        xid.mint(user1, username, 1);

        // Transfer to accumulate fees
        vm.startPrank(user2);
        mockToken.approve(address(xMoney), amount);
        xMoney.transferToken(username, amount, address(mockToken));
        vm.stopPrank();

        // Calculate expected fee
        uint256 expectedFee = (amount * FEE_RATE) / 10000;

        // Verify fees have accumulated
        assertEq(
            xMoney.getAccumulatedTokenFees(address(mockToken)),
            expectedFee
        );

        // Non-fee receiver cannot claim
        vm.prank(user1);
        vm.expectRevert("XMoney: Only fee receiver can claim fees");
        xMoney.claimTokenFees(address(mockToken));

        // Fee receiver claims fees
        uint256 feeReceiverBalanceBefore = mockToken.balanceOf(feeReceiver);
        vm.prank(feeReceiver);
        xMoney.claimTokenFees(address(mockToken));

        // Verify fees transferred to receiver
        assertEq(
            mockToken.balanceOf(feeReceiver) - feeReceiverBalanceBefore,
            expectedFee
        );

        // Verify accumulated fees cleared
        assertEq(xMoney.getAccumulatedTokenFees(address(mockToken)), 0);
    }

    function testClaimMultipleTokenFees() public {
        // Set up two tokens
        MockToken secondToken = new MockToken();
        secondToken.transfer(user2, 1000 * 10 ** 18);

        string memory username = "user1";
        uint256 amount1 = 100 * 10 ** 18;
        uint256 amount2 = 200 * 10 ** 18;

        // Register user
        vm.prank(mockController);
        xid.mint(user1, username, 1);

        // Transfer both tokens to accumulate fees
        vm.startPrank(user2);
        mockToken.approve(address(xMoney), amount1);
        xMoney.transferToken(username, amount1, address(mockToken));

        secondToken.approve(address(xMoney), amount2);
        xMoney.transferToken(username, amount2, address(secondToken));
        vm.stopPrank();

        // Calculate expected fees
        uint256 expectedFee1 = (amount1 * FEE_RATE) / 10000;
        uint256 expectedFee2 = (amount2 * FEE_RATE) / 10000;

        // Verify fees have accumulated
        assertEq(
            xMoney.getAccumulatedTokenFees(address(mockToken)),
            expectedFee1
        );
        assertEq(
            xMoney.getAccumulatedTokenFees(address(secondToken)),
            expectedFee2
        );

        // Prepare token array
        address[] memory tokens = new address[](2);
        tokens[0] = address(mockToken);
        tokens[1] = address(secondToken);

        // Fee receiver claims multiple token fees
        uint256 feeReceiverBalance1Before = mockToken.balanceOf(feeReceiver);
        uint256 feeReceiverBalance2Before = secondToken.balanceOf(feeReceiver);

        vm.prank(feeReceiver);
        xMoney.claimMultipleTokenFees(tokens);

        // Verify fees transferred to receiver
        assertEq(
            mockToken.balanceOf(feeReceiver) - feeReceiverBalance1Before,
            expectedFee1
        );
        assertEq(
            secondToken.balanceOf(feeReceiver) - feeReceiverBalance2Before,
            expectedFee2
        );

        // Verify accumulated fees cleared
        assertEq(xMoney.getAccumulatedTokenFees(address(mockToken)), 0);
        assertEq(xMoney.getAccumulatedTokenFees(address(secondToken)), 0);
    }

    function testClaimEthFees() public {
        string memory username = "user1";
        uint256 amount = 1 ether;

        // Register user
        vm.prank(mockController);
        xid.mint(user1, username, 1);

        // Transfer to accumulate ETH fees
        vm.prank(user2);
        xMoney.transferNativeToken{value: amount}(username);

        // Calculate expected fee
        uint256 expectedFee = (amount * FEE_RATE) / 10000;

        // Verify fees have accumulated
        assertEq(xMoney.getAccumulatedNativeTokenFees(), expectedFee);

        // Non-fee receiver cannot claim
        vm.prank(user1);
        vm.expectRevert("XMoney: Only fee receiver can claim fees");
        xMoney.claimNativeTokenFees();

        // Fee receiver claims fees
        uint256 feeReceiverBalanceBefore = feeReceiver.balance;
        vm.prank(feeReceiver);
        xMoney.claimNativeTokenFees();

        // Verify fees transferred to receiver
        assertEq(feeReceiver.balance - feeReceiverBalanceBefore, expectedFee);

        // Verify accumulated fees cleared
        assertEq(xMoney.getAccumulatedNativeTokenFees(), 0);
    }

    function testClaimFeesWithNoFees() public {
        // Try to claim non-existent fees
        vm.prank(feeReceiver);
        vm.expectRevert("XMoney: No token fees to claim");
        xMoney.claimTokenFees(address(mockToken));

        vm.prank(feeReceiver);
        vm.expectRevert("XMoney: No native token fees to claim");
        xMoney.claimNativeTokenFees();
    }

    function testClaimMultipleTokenFeesWithEmptyFees() public {
        // Prepare token array including tokens with no fees
        address[] memory tokens = new address[](2);
        tokens[0] = address(mockToken);
        tokens[1] = address(0x1234); // A token address with no fees

        // Accumulate some fees for the first token
        string memory username = "user1";
        uint256 amount = 100 * 10 ** 18;

        vm.prank(mockController);
        xid.mint(user1, username, 1);

        vm.startPrank(user2);
        mockToken.approve(address(xMoney), amount);
        xMoney.transferToken(username, amount, address(mockToken));
        vm.stopPrank();

        uint256 expectedFee = (amount * FEE_RATE) / 10000;
        uint256 feeReceiverBalanceBefore = mockToken.balanceOf(feeReceiver);

        // Batch claim fees including tokens with no fees
        vm.prank(feeReceiver);
        xMoney.claimMultipleTokenFees(tokens);

        // Verify fees transferred for tokens with fees
        assertEq(
            mockToken.balanceOf(feeReceiver) - feeReceiverBalanceBefore,
            expectedFee
        );
        assertEq(xMoney.getAccumulatedTokenFees(address(mockToken)), 0);

        // Second token should have no changes
        assertEq(xMoney.getAccumulatedTokenFees(tokens[1]), 0);
    }

    receive() external payable {}
}
