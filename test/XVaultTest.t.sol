// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {XVault} from "../src/XVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockXID {
    address public controller;
    mapping(address => string) private _addressToUsername;
    mapping(string => address) private _usernameToAddress;

    function setController(address _controller) external {
        controller = _controller;
    }

    function mint(address user, string memory username, uint256) external {
        require(msg.sender == controller, "Not controller");
        _addressToUsername[user] = username;
        _usernameToAddress[username] = user;
    }

    function getAddressByUsername(
        string memory username
    ) external view returns (address) {
        address owner = _usernameToAddress[username];
        require(owner != address(0), "Username not registered");
        return owner;
    }

    function getUsernameByAddress(
        address user
    ) external view returns (string memory) {
        string memory username = _addressToUsername[user];
        require(bytes(username).length > 0, "Address not registered");
        return username;
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract XVaultTest is Test {
    XVault public vault;
    MockXID public xid;
    MockERC20 public token;

    address constant CONTROLLER = address(0x123);
    address constant ALICE = address(0x456);
    string constant TEST_USERNAME = "test.user";
    uint256 constant INITIAL_BALANCE = 100 ether;
    uint256 constant FEE_RATE = 1000; // 10%
    uint256 constant MAX_INACTIVE_PERIOD = 365 days;

    event NativeTokenDeposited(
        bytes32 indexed usernameHash,
        string username,
        uint256 amount
    );

    event TokenDeposited(
        bytes32 indexed usernameHash,
        string username,
        address token,
        uint256 amount
    );

    event NativeTokenWithdrawn(
        bytes32 indexed usernameHash,
        string username,
        address to,
        uint256 amount
    );

    event TokenWithdrawn(
        bytes32 indexed usernameHash,
        string username,
        address token,
        address to,
        uint256 amount
    );

    event XidAddressUpdated(address oldXid, address newXid);

    event FeesClaimed(address indexed token, uint256 amount);


    function setUp() public {
        xid = new MockXID();
        xid.setController(CONTROLLER);
        vault = new XVault(address(xid), CONTROLLER);
        token = new MockERC20("Test Token", "TEST");

        vm.deal(ALICE, INITIAL_BALANCE);
        token.mint(ALICE, INITIAL_BALANCE);

        // Register test username
        vm.prank(CONTROLLER);
        xid.mint(ALICE, TEST_USERNAME, 1);
    }

    function testDepositAndWithdrawNativeToken() public {
        uint256 depositAmount = 1 ether;

        vm.prank(ALICE);
        vault.depositNativeToken{value: depositAmount}(TEST_USERNAME);

        // Verify balance
        assertEq(
            vault.nativeTokenBalances(keccak256(bytes(TEST_USERNAME))),
            depositAmount
        );
        assertEq(vault.getNativeTokenBalance(TEST_USERNAME), depositAmount);

        // Withdrawal test
        vm.prank(ALICE);
        uint256 balanceBefore = ALICE.balance;
        vault.withdrawNativeToken(TEST_USERNAME);

        // Calculate amount after deducting fee
        uint256 fee = (depositAmount * FEE_RATE) / 10000;
        uint256 expectedAmount = depositAmount - fee;

        // Verify withdrawal status
        assertEq(ALICE.balance - balanceBefore, expectedAmount);
        assertEq(vault.nativeTokenBalances(keccak256(bytes(TEST_USERNAME))), 0);
    }

    function testDepositAndWithdrawToken() public {
        uint256 depositAmount = 1000;

        vm.startPrank(ALICE);
        token.approve(address(vault), depositAmount);
        vault.depositToken(TEST_USERNAME, address(token), depositAmount);

        // Verify balance and token is automatically added to supported list
        assertEq(
            vault.tokenBalances(
                keccak256(bytes(TEST_USERNAME)),
                address(token)
            ),
            depositAmount
        );
        assertEq(
            vault.getTokenBalance(TEST_USERNAME, address(token)),
            depositAmount
        );

        // Withdrawal test
        uint256 balanceBefore = token.balanceOf(ALICE);
        vault.withdrawToken(TEST_USERNAME, address(token));
        vm.stopPrank();

        // Calculate amount after deducting fee
        uint256 fee = (depositAmount * FEE_RATE) / 10000;
        uint256 expectedAmount = depositAmount - fee;

        // Verify status after withdrawal
        assertEq(token.balanceOf(ALICE) - balanceBefore, expectedAmount);
        assertEq(
            vault.tokenBalances(
                keccak256(bytes(TEST_USERNAME)),
                address(token)
            ),
            0
        );
    }

    function testWithdrawUnauthorized() public {
        uint256 depositAmount = 1 ether;

        vm.prank(ALICE);
        vault.depositNativeToken{value: depositAmount}(TEST_USERNAME);

        // Try to withdraw using unauthorized address
        vm.prank(address(0x789));
        vm.expectRevert("XVault: Caller is not the XID owner");
        vault.withdrawNativeToken(TEST_USERNAME);
    }

    function testWithdrawEmptyBalance() public {
        vm.prank(ALICE);
        vm.expectRevert("XVault: No native token balance");
        vault.withdrawNativeToken(TEST_USERNAME);
    }

    function testWithdrawNativeTokenWithFee() public {
        uint256 depositAmount = 1 ether;

        vm.prank(ALICE);
        vault.depositNativeToken{value: depositAmount}(TEST_USERNAME);

        vm.prank(ALICE);
        uint256 balanceBefore = ALICE.balance;
        vault.withdrawNativeToken(TEST_USERNAME);

        uint256 fee = (depositAmount * FEE_RATE) / 10000;
        uint256 expectedAmount = depositAmount - fee;

        // Verify amount received by user (after deducting fee)
        assertEq(ALICE.balance - balanceBefore, expectedAmount);
    }

    function testWithdrawTokenWithFee() public {
        uint256 depositAmount = 1000;

        vm.startPrank(ALICE);
        token.approve(address(vault), depositAmount);
        vault.depositToken(TEST_USERNAME, address(token), depositAmount);

        uint256 balanceBefore = token.balanceOf(ALICE);
        vault.withdrawToken(TEST_USERNAME, address(token));
        vm.stopPrank();

        uint256 fee = (depositAmount * FEE_RATE) / 10000;
        uint256 expectedAmount = depositAmount - fee;

        // Verify amount received by user (after deducting fee)
        assertEq(token.balanceOf(ALICE) - balanceBefore, expectedAmount);
    }

    function testBatchDepositWithEvents() public {
        string[] memory usernames = new string[](2);
        usernames[0] = "user1";
        usernames[1] = "user2";

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        bytes32[] memory usernameHashes = new bytes32[](2);
        usernameHashes[0] = keccak256(bytes(usernames[0]));
        usernameHashes[1] = keccak256(bytes(usernames[1]));

        // Test ETH batch deposit events
        vm.recordLogs();
        vm.deal(ALICE, 3 ether);
        vm.prank(ALICE);
        vault.batchDepositNativeToken{value: 3 ether}(usernames, amounts);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        // Verify event signature
        assertEq(
            entries[0].topics[0],
            keccak256("BatchNativeTokenDeposited(string[],uint256[])")
        );

        // Test token batch deposit events
        vm.recordLogs();
        vm.startPrank(ALICE);
        token.approve(address(vault), 3 ether);
        vault.batchDepositToken(usernames, amounts, address(token));
        vm.stopPrank();

        entries = vm.getRecordedLogs();
        assertEq(entries.length, 3); // Approval + Transfer + BatchTokenDeposited
        // Verify last event (BatchTokenDeposited) signature
        assertEq(
            entries[2].topics[0],
            keccak256("BatchTokenDeposited(string[],uint256[],address)")
        );
        // Verify first event is Approval
        assertEq(
            entries[0].topics[0],
            keccak256("Approval(address,address,uint256)")
        );
        // Verify second event is Transfer
        assertEq(
            entries[1].topics[0],
            keccak256("Transfer(address,address,uint256)")
        );
    }

    // Add helper function for calculating username hash
    function _usernameHash(
        string memory username
    ) internal pure returns (bytes32) {
        return keccak256(bytes(username));
    }

    // Add withdrawal event tests
    function testWithdrawEvents() public {
        uint256 depositAmount = 1 ether;
        bytes32 usernameHash = _usernameHash(TEST_USERNAME);

        // First deposit some assets
        vm.startPrank(ALICE);
        vault.depositNativeToken{value: depositAmount}(TEST_USERNAME);
        token.approve(address(vault), depositAmount);
        vault.depositToken(TEST_USERNAME, address(token), depositAmount);

        // Calculate amount after deducting fee
        uint256 fee = (depositAmount * FEE_RATE) / 10000;
        uint256 expectedAmount = depositAmount - fee;

        // Test ETH withdrawal event
        vm.expectEmit(true, false, false, true);
        emit NativeTokenWithdrawn(usernameHash, TEST_USERNAME, ALICE, expectedAmount);
        vault.withdrawNativeToken(TEST_USERNAME);

        // Test token withdrawal event
        vm.expectEmit(true, false, false, true);
        emit TokenWithdrawn(
            usernameHash,
            TEST_USERNAME,
            address(token),
            ALICE,
            expectedAmount
        );
        vault.withdrawToken(TEST_USERNAME, address(token));
        vm.stopPrank();
    }

    function testBatchDepositNativeToken() public {
        string[] memory usernames = new string[](3);
        usernames[0] = "user1";
        usernames[1] = "user2";
        usernames[2] = "user3";

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        uint256 totalAmount = 6 ether;

        vm.deal(ALICE, totalAmount);
        vm.prank(ALICE);
        vault.batchDepositNativeToken{value: totalAmount}(usernames, amounts);

        // Verify each user's deposit amount
        assertEq(vault.getNativeTokenBalance("user1"), 1 ether);
        assertEq(vault.getNativeTokenBalance("user2"), 2 ether);
        assertEq(vault.getNativeTokenBalance("user3"), 3 ether);
    }

    function testBatchDepositToken() public {
        string[] memory usernames = new string[](3);
        usernames[0] = "user1";
        usernames[1] = "user2";
        usernames[2] = "user3";

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        uint256 totalAmount = 600;

        vm.startPrank(ALICE);
        token.approve(address(vault), totalAmount);
        vault.batchDepositToken(usernames, amounts, address(token));
        vm.stopPrank();

        // Verify each user's token deposit amount
        assertEq(vault.getTokenBalance("user1", address(token)), 100);
        assertEq(vault.getTokenBalance("user2", address(token)), 200);
        assertEq(vault.getTokenBalance("user3", address(token)), 300);
    }

    function testBatchDepositNativeTokenWithInvalidInput() public {
        string[] memory usernames = new string[](2);
        usernames[0] = "user1";
        usernames[1] = "user2";

        uint256[] memory amounts = new uint256[](3); // Length mismatch
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        vm.deal(ALICE, 6 ether);
        vm.prank(ALICE);
        vm.expectRevert("XVault: Arrays length mismatch");
        vault.batchDepositNativeToken{value: 6 ether}(usernames, amounts);
    }

    function testBatchDepositNativeTokenWithIncorrectValue() public {
        string[] memory usernames = new string[](2);
        usernames[0] = "user1";
        usernames[1] = "user2";

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        vm.deal(ALICE, 4 ether);
        vm.prank(ALICE);
        vm.expectRevert("XVault: Incorrect total amount");
        vault.batchDepositNativeToken{value: 4 ether}(usernames, amounts);
    }

    function testBatchDepositTokenWithInvalidInput() public {
        string[] memory usernames = new string[](2);
        usernames[0] = "user1";
        usernames[1] = "user2";

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        vm.prank(ALICE);
        vm.expectRevert("XVault: Arrays length mismatch");
        vault.batchDepositToken(usernames, amounts, address(token));
    }

    function testWithdrawAll() public {
        // Deposit some ETH and tokens
        vm.deal(ALICE, 1 ether);
        vm.startPrank(ALICE);
        vault.depositNativeToken{value: 1 ether}(TEST_USERNAME);
        token.approve(address(vault), 100);
        vault.depositToken(TEST_USERNAME, address(token), 100);

        // Record balance before withdrawal
        uint256 ethBalanceBefore = ALICE.balance;
        uint256 tokenBalanceBefore = token.balanceOf(ALICE);

        // Prepare token array
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        // Withdraw all assets at once
        vault.withdrawAll(TEST_USERNAME, tokens);
        vm.stopPrank();

        // Calculate expected net amount (after deducting fees)
        uint256 ethFee = (1 ether * FEE_RATE) / 10000;
        uint256 tokenFee = (100 * FEE_RATE) / 10000;

        // Verify balance after withdrawal
        assertEq(ALICE.balance - ethBalanceBefore, 1 ether - ethFee);
        assertEq(token.balanceOf(ALICE) - tokenBalanceBefore, 100 - tokenFee);

        // Verify contract balance is cleared
        assertEq(vault.getNativeTokenBalance(TEST_USERNAME), 0);
        assertEq(vault.getTokenBalance(TEST_USERNAME, address(token)), 0);
    }

    function testSetXidAddress() public {
        // Create a new MockXID contract
        MockXID newXid = new MockXID();
        address oldXidAddress = address(xid);

        // Only owner should be able to update XID address
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                ALICE
            )
        );
        vault.setXidAddress(address(newXid));

        // Test successful update
        vm.expectEmit(true, true, false, false);
        emit XidAddressUpdated(oldXidAddress, address(newXid));
        vault.setXidAddress(address(newXid));

        // Verify the new XID address
        assertEq(address(vault.xid()), address(newXid));
    }


    function testClaimTokenFees() public {
        uint256 depositAmount = 1000;

        // First deposit some tokens
        vm.startPrank(ALICE);
        token.approve(address(vault), depositAmount);
        vault.depositToken(TEST_USERNAME, address(token), depositAmount);

        // Withdraw tokens and generate fees
        vault.withdrawToken(TEST_USERNAME, address(token));
        vm.stopPrank();

        // Calculate expected fee
        uint256 expectedFee = (depositAmount * FEE_RATE) / 10000;

        // Verify fees have accumulated
        assertEq(vault.getAccumulatedTokenFees(address(token)), expectedFee);

        // Non-fee receiver tries to claim fees
        vm.prank(ALICE);
        vm.expectRevert("XVault: Only fee receiver can claim fees");
        vault.claimTokenFees(address(token));

        // Fee receiver claims fees
        uint256 feeReceiverBalanceBefore = token.balanceOf(CONTROLLER);
        vm.expectEmit(true, false, false, true);
        emit FeesClaimed(address(token), expectedFee);
        vm.prank(CONTROLLER);
        vault.claimTokenFees(address(token));

        // Verify fees transferred to receiver
        assertEq(
            token.balanceOf(CONTROLLER) - feeReceiverBalanceBefore,
            expectedFee
        );

        // Verify accumulated fees cleared
        assertEq(vault.getAccumulatedTokenFees(address(token)), 0);
    }

    function testClaimMultipleTokenFees() public {
        // Create second test token
        MockERC20 token2 = new MockERC20("Test Token 2", "TEST2");
        token2.mint(ALICE, INITIAL_BALANCE);

        uint256 depositAmount1 = 1000;
        uint256 depositAmount2 = 2000;

        // Deposit and withdraw both tokens to generate fees
        vm.startPrank(ALICE);

        // First token
        token.approve(address(vault), depositAmount1);
        vault.depositToken(TEST_USERNAME, address(token), depositAmount1);
        vault.withdrawToken(TEST_USERNAME, address(token));

        // Second token
        token2.approve(address(vault), depositAmount2);
        vault.depositToken(TEST_USERNAME, address(token2), depositAmount2);
        vault.withdrawToken(TEST_USERNAME, address(token2));

        vm.stopPrank();

        // Calculate expected fees
        uint256 expectedFee1 = (depositAmount1 * FEE_RATE) / 10000;
        uint256 expectedFee2 = (depositAmount2 * FEE_RATE) / 10000;

        // Verify fees have accumulated
        assertEq(vault.getAccumulatedTokenFees(address(token)), expectedFee1);
        assertEq(vault.getAccumulatedTokenFees(address(token2)), expectedFee2);

        // Prepare token array
        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(token2);

        // Record balance before withdrawal
        uint256 feeReceiverBalance1Before = token.balanceOf(CONTROLLER);
        uint256 feeReceiverBalance2Before = token2.balanceOf(CONTROLLER);

        // Batch claim fees
        vm.prank(CONTROLLER);
        vault.claimMultipleTokenFees(tokens);

        // Verify fees transferred to receiver
        assertEq(
            token.balanceOf(CONTROLLER) - feeReceiverBalance1Before,
            expectedFee1
        );
        assertEq(
            token2.balanceOf(CONTROLLER) - feeReceiverBalance2Before,
            expectedFee2
        );

        // Verify accumulated fees cleared
        assertEq(vault.getAccumulatedTokenFees(address(token)), 0);
        assertEq(vault.getAccumulatedTokenFees(address(token2)), 0);
    }

    function testClaimNativeTokenFees() public {
        uint256 depositAmount = 1 ether;

        // First deposit some ETH
        vm.prank(ALICE);
        vault.depositNativeToken{value: depositAmount}(TEST_USERNAME);

        // Withdraw ETH and generate fees
        vm.prank(ALICE);
        vault.withdrawNativeToken(TEST_USERNAME);

        // Calculate expected fee
        uint256 expectedFee = (depositAmount * FEE_RATE) / 10000;

        // Verify fees have accumulated
        assertEq(vault.getAccumulatedNativeTokenFees(), expectedFee);

        // Non-fee receiver tries to claim fees
        vm.prank(ALICE);
        vm.expectRevert("XVault: Only fee receiver can claim fees");
        vault.claimNativeTokenFees();

        // Fee receiver claims fees
        uint256 feeReceiverBalanceBefore = CONTROLLER.balance;
        vm.expectEmit(true, false, false, true);
        emit FeesClaimed(address(0), expectedFee);
        vm.prank(CONTROLLER);
        vault.claimNativeTokenFees();

        // Verify fees transferred to receiver
        assertEq(CONTROLLER.balance - feeReceiverBalanceBefore, expectedFee);

        // Verify accumulated fees cleared
        assertEq(vault.getAccumulatedNativeTokenFees(), 0);
    }

    function testClaimFeesWithNoFees() public {
        // Try to claim non-existent fees
        vm.prank(CONTROLLER);
        vm.expectRevert("XVault: No token fees to claim");
        vault.claimTokenFees(address(token));

        vm.prank(CONTROLLER);
        vm.expectRevert("XVault: No native token fees to claim");
        vault.claimNativeTokenFees();
    }

    function testClaimMultipleTokenFeesWithEmptyFees() public {
        // Prepare token array including a token with no fees
        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(0x1234); // Token address with no fees

        // Accumulate some fees for the first token
        uint256 depositAmount = 1000;

        vm.startPrank(ALICE);
        token.approve(address(vault), depositAmount);
        vault.depositToken(TEST_USERNAME, address(token), depositAmount);
        vault.withdrawToken(TEST_USERNAME, address(token));
        vm.stopPrank();

        uint256 expectedFee = (depositAmount * FEE_RATE) / 10000;
        uint256 feeReceiverBalanceBefore = token.balanceOf(CONTROLLER);

        // Batch claim fees
        vm.prank(CONTROLLER);
        vault.claimMultipleTokenFees(tokens);

        // Verify fees transferred for tokens with fees
        assertEq(
            token.balanceOf(CONTROLLER) - feeReceiverBalanceBefore,
            expectedFee
        );
        assertEq(vault.getAccumulatedTokenFees(address(token)), 0);

        // Second token has no changes
        assertEq(vault.getAccumulatedTokenFees(tokens[1]), 0);
    }

    receive() external payable {}
}
